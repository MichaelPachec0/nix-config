#!/usr/bin/env bash
# Desktop-responsiveness matrix: which tuning keeps the GUI usable during a
# large build.
#
# This supersedes ab-matrix.sh for that question. ab-matrix.sh measured fio's
# own read latency under a synthetic load, which turned out to answer a
# different question badly:
#
#   - the load, the probe and everything else ran under one sudo'd cgroup, so
#     user.slice never did I/O, never missed its io.latency target, and never
#     throttled a peer. The iolat factor was structurally incapable of showing
#     an effect and duly reported noise.
#   - the burners ran at normal priority, so nix-daemon's SCHED_IDLE and idle
#     I/O class -- the actual mechanisms that protect the desktop during builds
#     -- were not exercised at all.
#   - read p99 over one repetition spanned 218us to 2572us, a 12x range, so a
#     single outlier cell buried every real effect.
#
# What changed here:
#
#   LOAD is a real `nix build`, four concurrent derivations with unique markers
#   so nothing is served from cache. Driven through nix-daemon, so builders
#   inherit the genuine SCHED_IDLE, IOSchedClass=idle and MemoryHigh=8G. Four
#   jobs x 4 cores reproduces the configured max-jobs=4/cores=4 width; a single
#   build would use 4 of 16 threads and under-load the machine.
#
#   PROBE runs in user.slice, as the user, so io.latency finally has something
#   to protect and the protection can be observed.
#
#   METRICS are PSI `total` deltas plus deadline misses. PSI totals are
#   monotonic accumulators of stalled microseconds, so one bad moment ADDS to
#   the count instead of distorting a percentile. That is what makes a single
#   repetition readable where the fio design needed many.
#
# FACTORS
#   nvme    bfq | kyber | adios        /sys/block/nvme0n1/queue/scheduler
#   dirty   low (64M/16M) | high (256M/64M)
#   sched   flash | eevdf              systemctl start/stop scx
#   iolat   on (10ms) | off            user.slice io.latency
#   cpuw    on | off                   CPUWeight on the slices
#
#   3 x 2 x 2 x 2 x 2 = 48 cells.
#
# The cpuw factor is the one lever here that has never been tried. memory.nix
# correctly notes that lowering CPUWeight on nix-daemon.service does nothing
# useful, because cgroup weights rank among siblings and its siblings are other
# system.slice units rather than the desktop. But user.slice and system.slice
# ARE siblings under the root cgroup, so weighting the SLICES is the cross-tree
# control that reasoning implies exists. Both currently sit at the default 100.
set -uo pipefail

# A systemd unit inherits systemd's own default PATH, which on NixOS is two
# entries deep: /bin holds sh and /usr/bin holds env, and that is the whole of
# it. No coreutils, no util-linux, no systemctl, no nix. Launched with
# `systemd-run --unit=...` -- the only way to survive a four-hour run without
# holding a terminal open for it -- preflight dies on `dd` and `dirname`
# before it checks anything. Put the system profile in front unconditionally;
# it is a no-op when launched from a login shell that already has it.
PATH="/run/wrappers/bin:/run/current-system/sw/bin:${PATH:-}"
export PATH

readonly NVME_DEV="nvme0n1"
readonly NVME_MAJMIN="259:0"
readonly SCHED_PATH="/sys/block/${NVME_DEV}/queue/scheduler"
readonly USER_SLICE="/sys/fs/cgroup/user.slice"
readonly SYS_SLICE="/sys/fs/cgroup/system.slice"
readonly IOLAT_PATH="${USER_SLICE}/io.latency"
readonly ZRAM_SYS="/sys/block/zram0"

SETTLE="${SETTLE:-45}"       # let the build reach steady compile before measuring
MEASURE="${MEASURE:-210}"    # must finish well inside the build (~356s observed)
REPS="${REPS:-1}"
BUILD_JOBS="${BUILD_JOBS:-4}"
BUDGET_HOURS="${BUDGET_HOURS:-5}"
PROBE_USER="${PROBE_USER:-michael}"

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# Only /home, /persist and /nix survive a reboot on this host; anything else is
# a fresh subvolume every boot. A four-hour run must not write its results to a
# filesystem that a reboot will erase.
OUTDIR="${OUTDIR:-$REPO_ROOT/.ab-latency/results}"
WORKDIR="${WORKDIR:-$REPO_ROOT/.ab-latency/work}"
READFILE="$WORKDIR/probe-read.bin"
FLAKE="${FLAKE:-/home/michael/nix-config}"

# python3 is not in the system profile and not in this user's profile either;
# it only ever appears on PATH by accident of a devshell. The probe and both
# report writers need it, so resolve it once to an absolute path and fail in
# preflight rather than at cell 37 of 48.
PY3="${PY3:-}"

resolve_python() {
  local c
  for c in "$PY3" \
           /run/current-system/sw/bin/python3 \
           "/etc/profiles/per-user/${PROBE_USER}/bin/python3" \
           "$(command -v python3 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  # Nothing installed anywhere: materialise one. The `nixpkgs` registry entry
  # is system-scoped and already pinned to a store path by this flake, so this
  # resolves with no network, no git and no HOME -- all three of which a
  # systemd unit lacks in the shape a login shell has them. Deliberately not
  # --inputs-from "$FLAKE": that would re-copy a dirty working tree into the
  # store and needs a readable git config, for the identical output path.
  # --out-link makes it a GC root so a stray collect-garbage cannot pull the
  # interpreter out from under a four-hour run.
  local out
  mkdir -p "$WORKDIR" 2>/dev/null || true
  out="$(NIX_REMOTE=daemon nix build 'nixpkgs#python3' \
    --out-link "$WORKDIR/python3" --print-out-paths 2>/dev/null)" || return 1
  [ -n "$out" ] && [ -x "$out/bin/python3" ] && { echo "$out/bin/python3"; return 0; }
  return 1
}

# True when `nix build` will hand work to nix-daemon.service rather than
# building it inside this process.
#
# --json is deliberate: the human-readable output of `nix store info` goes to
# STDERR, not stdout, so a `2>/dev/null` filter discards the very text worth
# matching and the check can then only ever fail. --json writes a stable object
# to stdout.
#
# The absence of a pipe is deliberate too: `grep -q` exits at the first match
# and SIGPIPEs its producer, and `set -o pipefail` reports that as a failed
# pipeline -- so the naive form fails exactly when it matched.
ensure_python() {
  [ -n "$PY3" ] && [ -x "$PY3" ] && return 0
  PY3="$(resolve_python)" || return 1
  [ -n "$PY3" ] && [ -x "$PY3" ]
}

daemon_ok() {
  local info
  info="$(NIX_REMOTE=daemon nix store info --json 2>/dev/null)" || return 1
  case "$info" in
    *'"url":"daemon"'*) return 0 ;;
  esac
  return 1
}

# bfq is deliberately absent. This matrix is what excluded it -- 13x worse on
# desktop I/O stall than either survivor -- and memory.nix has since dropped
# boot.kernelModules = ["bfq"] as a result, so the module is not loaded and the
# scheduler cannot be selected at all. Leaving it here made preflight fail with
# "nvme scheduler 'bfq' unavailable" and the whole harness unrunnable. The
# numbers are recorded in memory.nix; re-running the arm would need the module
# back first.
NVME_LEVELS=(kyber adios)
DIRTY_LEVELS=(low high)
SCHED_LEVELS=(flash eevdf)
IOLAT_LEVELS=(on off)
CPUW_LEVELS=(on off)

# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

cell_count() {
  echo $((${#NVME_LEVELS[@]} * ${#DIRTY_LEVELS[@]} * ${#SCHED_LEVELS[@]} * ${#IOLAT_LEVELS[@]} * ${#CPUW_LEVELS[@]}))
}

cell_seconds() { echo $((SETTLE + MEASURE + 30)); }

estimate_seconds() { echo $(($(cell_count) * $1 * $(cell_seconds))); }

fmt_hms() { printf '%dh%02dm' $(($1 / 3600)) $((($1 % 3600) / 60)); }

reps_that_fit() {
  local ceiling="$1" r=0 i
  for i in 1 2 3 4; do
    [ "$(estimate_seconds "$i")" -le "$ceiling" ] && r="$i"
  done
  echo "$r"
}

shuffle_seeded() { shuf --random-source=<(yes "$1"); }

block_cells() {
  local n d s i c
  for n in "${NVME_LEVELS[@]}"; do
    for d in "${DIRTY_LEVELS[@]}"; do
      for s in "${SCHED_LEVELS[@]}"; do
        for i in "${IOLAT_LEVELS[@]}"; do
          for c in "${CPUW_LEVELS[@]}"; do
            echo "$n:$d:$s:$i:$c"
          done
        done
      done
    done
  done
}

dirty_bytes_for() {
  case "$1" in
    low) echo "67108864 16777216" ;;
    high) echo "268435456 67108864" ;;
    *) return 1 ;;
  esac
}

# PSI: field 'total=' from the `some` line, in microseconds. A monotonic
# accumulator of time at least one task in the cgroup was stalled.
# Returns EMPTY when the file is missing or unparseable -- never 0. A 0 here
# would flow into the delta as 0-0 and record "the desktop never stalled" for
# every row, which reads as a clean result rather than as a broken probe. Same
# failure class as the hardcoded hwmon index that silently logged temp_c=0 for
# a whole run.
psi_total() { # <cgroup path> <cpu|io|memory> <some|full>
  [ -r "$1/$2.pressure" ] || return 0
  awk -v want="$3" '$1 == want { for (i = 2; i <= NF; i++) if ($i ~ /^total=/) { sub(/^total=/, "", $i); print $i } }' \
    "$1/$2.pressure" 2>/dev/null
}

# Resolve a hwmon by NAME, never by index. The previous harness hardcoded
# hwmon3 for zenpower; after a reboot hwmon3 was BAT0, which has no temp1_input,
# so every row recorded temp_c=0 -- on the machine where thermal throttling at
# 90C turned out to be the dominant effect.
hwmon_temp() { # <name>
  local d n
  for d in /sys/class/hwmon/hwmon*; do
    n="$(cat "$d/name" 2>/dev/null || true)"
    if [ "$n" = "$1" ] && [ -r "$d/temp1_input" ]; then
      awk '{printf "%.1f", $1 / 1000}' "$d/temp1_input"
      return 0
    fi
  done
  echo ""    # empty, not 0: absent is not the same as cold
}

# ---------------------------------------------------------------------------
# State capture / restore
# ---------------------------------------------------------------------------

ORIG_SCHED=""; ORIG_DIRTY=""; ORIG_DIRTY_BG=""; ORIG_IOLAT=""
ORIG_SCX=""; ORIG_CPUW_USER=""; ORIG_CPUW_SYS=""
RESTORED=0

capture_state() {
  ORIG_SCHED="$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$SCHED_PATH")"
  ORIG_DIRTY="$(cat /proc/sys/vm/dirty_bytes)"
  ORIG_DIRTY_BG="$(cat /proc/sys/vm/dirty_background_bytes)"
  ORIG_IOLAT="$(cat "$IOLAT_PATH" 2>/dev/null || echo "")"
  ORIG_SCX="$(systemctl is-active scx 2>/dev/null || true)"
  ORIG_CPUW_USER="$(cat "$USER_SLICE/cpu.weight" 2>/dev/null || echo 100)"
  ORIG_CPUW_SYS="$(cat "$SYS_SLICE/cpu.weight" 2>/dev/null || echo 100)"
  echo "captured: sched=$ORIG_SCHED dirty=$ORIG_DIRTY/$ORIG_DIRTY_BG iolat='$ORIG_IOLAT'"
  echo "          scx=$ORIG_SCX cpu.weight user=$ORIG_CPUW_USER system=$ORIG_CPUW_SYS"
  # A prior aborted run can leave the machine tuned, and this function would
  # then adopt that as "original" and faithfully restore back to it at the end.
  local drift=""
  { [ "$ORIG_CPUW_USER" = "100" ] && [ "$ORIG_CPUW_SYS" = "100" ]; } || drift="cpu.weight "
  [ -z "$ORIG_IOLAT" ] || drift="${drift}io.latency "
  [ -z "$drift" ] || {
    echo "WARN: baseline is not stock (${drift}already set); a previous run"
    echo "      likely did not restore. The matrix itself is unaffected -- every"
    echo "      cell sets all five factors -- but the final restore returns HERE."
  }
  echo "observed: zram $(awk -v d="$(cat $ZRAM_SYS/disksize)" -v r="$(awk '/MemTotal/{print $2}' /proc/meminfo)" 'BEGIN{printf "%.0f", d/1024/r*100}')% of RAM (never modified)"
}

on_signal() {
  echo "" >&2
  echo "signal received -- restoring and stopping" >&2
  restore_state
  exit 130
}

restore_state() {
  [ "$RESTORED" -eq 1 ] && return 0
  RESTORED=1
  echo ""
  echo "=== restoring ==="
  stop_load || true
  [ -n "$ORIG_SCHED" ] && echo "$ORIG_SCHED" > "$SCHED_PATH" 2>/dev/null
  sysctl -q -w "vm.dirty_bytes=$ORIG_DIRTY" "vm.dirty_background_bytes=$ORIG_DIRTY_BG" 2>/dev/null
  if [ -n "$ORIG_IOLAT" ]; then
    echo "$ORIG_IOLAT" > "$IOLAT_PATH" 2>/dev/null
  else
    # Empty means io.latency was UNSET. "Unset" is restored by writing a zero
    # target, which removes the entry; the old `[ -n ... ] &&` guard read it as
    # "nothing to do" and silently left the last cell's throttle in place.
    echo "$NVME_MAJMIN target=0" > "$IOLAT_PATH" 2>/dev/null
  fi
  systemctl set-property --runtime user.slice "CPUWeight=$ORIG_CPUW_USER" 2>/dev/null
  systemctl set-property --runtime system.slice "CPUWeight=$ORIG_CPUW_SYS" 2>/dev/null
  # services.scx.enable is false now, so there may be no scx unit at all.
  # `systemctl start scx` on a missing unit is a hard failure, not a no-op, so
  # ask whether it exists before touching it rather than relying on 2>/dev/null
  # to hide the noise.
  if systemctl cat scx >/dev/null 2>&1; then
    if [ "$ORIG_SCX" = "active" ]; then
      systemctl start scx 2>/dev/null || true
    else
      systemctl stop scx 2>/dev/null || true
    fi
  fi
  echo "  sched:  $(sed -n 's/.*\[\(.*\)\].*/\1/p' "$SCHED_PATH")"
  echo "  dirty:  $(cat /proc/sys/vm/dirty_bytes) / $(cat /proc/sys/vm/dirty_background_bytes)"
  echo "  iolat:  $(cat "$IOLAT_PATH" 2>/dev/null || echo unset)"
  echo "  cpuw:   user=$(cat "$USER_SLICE/cpu.weight") system=$(cat "$SYS_SLICE/cpu.weight")"
  echo "  scx:    $(systemctl is-active scx 2>/dev/null || echo inactive)"
}

# ---------------------------------------------------------------------------
# Applying a configuration
# ---------------------------------------------------------------------------

apply_nvme() {
  echo "$1" > "$SCHED_PATH" || return 1
  [ "$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$SCHED_PATH")" = "$1" ] || {
    echo "ERROR: nvme scheduler did not take '$1'" >&2; return 1; }
}

apply_dirty() {
  local pair; pair="$(dirty_bytes_for "$1")" || return 1
  sysctl -q -w "vm.dirty_bytes=${pair% *}" "vm.dirty_background_bytes=${pair#* }"
}

apply_iolat() {
  case "$1" in
    on) echo "$NVME_MAJMIN target=10000" > "$IOLAT_PATH" ;;
    off) echo "$NVME_MAJMIN target=0" > "$IOLAT_PATH" ;;
    *) return 1 ;;
  esac
}

# The untested lever. 20 vs 1000 is a 50:1 ratio, deliberately aggressive: a
# timid split would land inside the noise and prove nothing either way.
apply_cpuw() {
  case "$1" in
    on)
      systemctl set-property --runtime system.slice CPUWeight=20 || return 1
      systemctl set-property --runtime user.slice CPUWeight=1000 || return 1
      ;;
    off)
      systemctl set-property --runtime system.slice CPUWeight=100 || return 1
      systemctl set-property --runtime user.slice CPUWeight=100 || return 1
      ;;
    *) return 1 ;;
  esac
}

apply_sched() {
  local i
  case "$1" in
    flash)
      systemctl start scx || return 1
      for i in $(seq 1 20); do
        [ "$(cat /sys/kernel/sched_ext/state 2>/dev/null)" = "enabled" ] && return 0
        sleep 1
      done
      echo "ERROR: scx did not attach in 20s" >&2; return 1 ;;
    eevdf)
      systemctl stop scx || return 1
      for i in $(seq 1 15); do
        [ "$(cat /sys/kernel/sched_ext/state 2>/dev/null)" != "enabled" ] && return 0
        sleep 1
      done
      echo "ERROR: sched_ext still attached" >&2; return 1 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Load: real nix builds through nix-daemon
# ---------------------------------------------------------------------------

BUILD_PIDS=()

# Derivation paths for the whole run, resolved ONCE before any cell is timed.
LOAD_DRVS=()
LOAD_NEXT=0

# One evaluation for every marker the run will ever need.
#
# Each `nix build --expr` that calls builtins.getFlake on this repo pays a full
# evaluation of nix-config and nixpkgs, because a DIRTY git tree has no
# eval-cache fingerprint and is therefore never cached. Measured on this host:
# four concurrent evaluations were still running at 150 seconds with not one
# rustc process in existence, so a 45s settle plus a 210s window measured four
# nix evaluations rather than four Rust builds and every cell recorded
# builds_alive=0. Resolving all the derivations up front moves that cost
# outside the measured window and lets each cell start compiling at once.
resolve_load_drvs() { # <count>
  local want="$1" markers i out
  markers=""
  for i in $(seq 1 "$want"); do
    markers="$markers \"run$$-$i\""
  done
  echo "resolving $want load derivations (one evaluation, not $want)..."
  out="$(NIX_REMOTE=daemon nix eval --impure --json --expr \
    "map (d: d.drvPath) (import ${SCRIPT_DIR}/ncspot-load.nix { flake = \"${FLAKE}\"; markers = [ $markers ]; })" \
    2>/dev/null)" || return 1
  # No jq dependency: the value is a flat JSON array of store paths.
  mapfile -t LOAD_DRVS < <(echo "$out" | tr ',' '\n' | grep -o '/nix/store/[^"]*\.drv')
  [ "${#LOAD_DRVS[@]}" -eq "$want" ] || {
    echo "FAIL: resolved ${#LOAD_DRVS[@]} derivations, wanted $want" >&2
    return 1
  }
  echo "  ${#LOAD_DRVS[@]} derivations ready"
}

start_load() { # <unused-marker-prefix, kept for call compatibility>
  local j drv
  BUILD_PIDS=()
  for j in $(seq 1 "$BUILD_JOBS"); do
    drv="${LOAD_DRVS[$LOAD_NEXT]:-}"
    LOAD_NEXT=$((LOAD_NEXT + 1))
    if [ -z "$drv" ]; then
      echo "ERROR: ran out of pre-resolved load derivations" >&2
      return 1
    fi
    # Building a .drv path directly: no expression, so no evaluation. The ^*
    # selector asks for every output.
    NIX_REMOTE=daemon nix build --no-link "${drv}^*" >/dev/null 2>&1 &
    BUILD_PIDS+=($!)
  done
}

stop_load() {
  local p
  for p in "${BUILD_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  BUILD_PIDS=()
  # nix build forwards work to the daemon; killing the client leaves the
  # builder running, so the actual compilers have to go too or the next cell
  # starts against a machine that is still loaded from the previous one.
  pkill -f 'ncspot-1.3.4' 2>/dev/null || true
  pkill -x rustc 2>/dev/null || true
  sleep 3
}

# ---------------------------------------------------------------------------
# Measurement
# ---------------------------------------------------------------------------

run_cell() { # nvme dirty sched iolat cpuw rep
  local nvme="$1" dirty="$2" sched="$3" iolat="$4" cpuw="$5" rep="$6"

  apply_nvme "$nvme" || return 1
  apply_dirty "$dirty" || return 1
  apply_iolat "$iolat" || return 1
  apply_cpuw "$cpuw" || return 1
  apply_sched "$sched" || return 1

  start_load "c${rep}-$(date +%s)"
  sleep "$SETTLE"

  local cpu0 io0 mem0 iof0
  cpu0="$(psi_total "$USER_SLICE" cpu some)"
  io0="$(psi_total "$USER_SLICE" io some)"
  iof0="$(psi_total "$USER_SLICE" io full)"
  mem0="$(psi_total "$USER_SLICE" memory some)"
  # Fail the cell loudly rather than recording zeroes that would read as "the
  # desktop never stalled".
  if [ -z "$cpu0" ] || [ -z "$io0" ] || [ -z "$mem0" ]; then
    echo "ERROR: PSI baseline unreadable (cpu='$cpu0' io='$io0' mem='$mem0')" >&2
    stop_load
    return 1
  fi

  # Probe runs in user.slice, as the user: that is what makes io.latency
  # protection observable rather than theoretical.
  local probe
  probe="$(systemd-run --scope --quiet --collect \
    --slice=user.slice --uid="$PROBE_USER" \
    "$PY3" "$SCRIPT_DIR/latency-probe.py" "$MEASURE" "$READFILE" 2>/dev/null)"

  local cpu1 io1 mem1 iof1
  cpu1="$(psi_total "$USER_SLICE" cpu some)"
  io1="$(psi_total "$USER_SLICE" io some)"
  iof1="$(psi_total "$USER_SLICE" io full)"
  mem1="$(psi_total "$USER_SLICE" memory some)"

  local temp builds_alive
  temp="$(hwmon_temp zenpower)"
  # If the builds finished early the tail of the window measured an idle box,
  # which would flatter this arm. Recorded so such rows can be discarded.
  builds_# `pgrep -c` prints 0 AND exits 1 when nothing matches, so `|| echo 0`
  # appended a SECOND 0 and the value became "0\n0". That newline landed
  # mid-row and split every CSV line in two. `|| true` keeps pgrep's own
  # count and swallows only the exit status.
  alive="$(pgrep -c -x rustc 2>/dev/null || true)"
  alive="${alive:-0}"

  stop_load

  local pcpu pio piof pmem
  pcpu=$((cpu1 - cpu0)); pio=$((io1 - io0)); piof=$((iof1 - iof0)); pmem=$((mem1 - mem0))

  "$PY3" - "$rep" "$nvme" "$dirty" "$sched" "$iolat" "$cpuw" \
    "$pcpu" "$pio" "$piof" "$pmem" "$temp" "$builds_alive" "$probe" <<'PY'
import json, sys
a = sys.argv[1:]
rep, nvme, dirty, sched, iolat, cpuw, pcpu, pio, piof, pmem, temp, alive = a[:12]
raw = a[12] if len(a) > 12 else ""
try:
    p = json.loads(raw) if raw.strip() else {}
except Exception:
    p = {}
print(",".join(str(x) for x in [
    rep, nvme, dirty, sched, iolat, cpuw,
    pcpu, pio, piof, pmem,
    p.get("misses_120hz", ""), p.get("misses_60hz", ""), p.get("max_stall_ms", ""),
    p.get("wake_p99_us", ""), p.get("wake_p999_us", ""), p.get("read_p99_us", ""),
    p.get("wakeups", ""), temp, alive,
]))
PY
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

preflight() {
  local fail=0 d mp c
  [ "$(id -u)" -eq 0 ] || { echo "FAIL: must run as root" >&2; fail=1; }

  # Every external command the run reaches for, checked up front. Under
  # systemd-run this is the difference between failing now and failing at the
  # first cell with a bare "dd: command not found".
  for c in awk cat chown date dd dirname findmnt grep mkdir nix pgrep pkill \
           readlink sed seq shuf sleep sort sysctl systemctl systemd-run; do
    command -v "$c" >/dev/null || { echo "FAIL: '$c' not on PATH" >&2; fail=1; }
  done

  ensure_python || {
    echo "FAIL: no usable python3. The probe and both report writers need one." >&2
    echo "      Set PY3=/path/to/python3, or install one system-wide." >&2
    fail=1
  }
  [ -n "$PY3" ] && echo "python3:  $PY3"
  id "$PROBE_USER" >/dev/null 2>&1 || { echo "FAIL: no such user '$PROBE_USER'" >&2; fail=1; }
  [ "$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo 0)" = "1" ] || {
    echo "FAIL: not on AC -- TLP changes governor/boost/ASPM at the transition," >&2
    echo "      which would alias a power-state change onto a factor." >&2; fail=1; }
  local n
  for n in "${NVME_LEVELS[@]}"; do
    grep -qw "$n" "$SCHED_PATH" || { echo "FAIL: nvme scheduler '$n' unavailable" >&2; fail=1; }
  done
  [ -w "$IOLAT_PATH" ] || { echo "FAIL: $IOLAT_PATH not writable" >&2; fail=1; }
  local pf
  for pf in cpu io memory; do
    [ -r "$USER_SLICE/$pf.pressure" ] || { echo "FAIL: PSI $pf unavailable on user.slice" >&2; fail=1; }
  done
  # The load only stands in for "a large build" if the compilers actually run
  # under nix-daemon.service. Its SCHED_IDLE, idle ioprio and MemoryHigh are
  # three of the mechanisms this matrix exists to judge, and root does not get
  # them for free -- see start_load. Assert the routing rather than trust it.
  if ! daemon_ok; then
    echo "FAIL: cannot reach the nix daemon; the load would build in this" >&2
    echo "      process's cgroup and the iolat/cpuw factors would be invalid." >&2
    fail=1
  fi
  local prop want got
  for prop in "CPUSchedulingPolicy=5" "IOSchedulingClass=3" "MemoryHigh=8589934592"; do
    want="${prop#*=}"
    got="$(systemctl show nix-daemon.service -p "${prop%%=*}" --value 2>/dev/null)"
    [ "$got" = "$want" ] || echo "WARN: nix-daemon.service ${prop%%=*}='$got', expected '$want'" >&2
  done

  [ -n "$(hwmon_temp zenpower)" ] || echo "WARN: zenpower hwmon not found; temp column will be empty" >&2

  mkdir -p "$OUTDIR" "$WORKDIR"
  for d in "$OUTDIR" "$WORKDIR"; do
    mp="$(findmnt -no TARGET --target "$d" 2>/dev/null)"
    case "$mp" in
      /home | /persist | /nix) ;;
      "") echo "FAIL: cannot resolve mountpoint for $d" >&2; fail=1 ;;
      *) echo "FAIL: $d is on '$mp', wiped on reboot" >&2; fail=1 ;;
    esac
  done
  # 512M of incompressible data for the probe to read from.
  if [ ! -f "$READFILE" ]; then
    echo "creating probe read file (512M)..."
    dd if=/dev/urandom of="$READFILE" bs=1M count=512 status=none || fail=1
  fi
  [ -n "${SUDO_UID:-}" ] && chown -R "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" "$(dirname "$OUTDIR")" 2>/dev/null
  return "$fail"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_estimate() {
  local ceiling=$((BUDGET_HOURS * 3600)) r est
  echo "cells per rep:    $(cell_count)  (nvme 3 x dirty 2 x sched 2 x iolat 2 x cpuw 2)"
  echo "seconds per cell: $(cell_seconds)  (settle $SETTLE + measure $MEASURE + 30 apply/kill)"
  echo "build load:       $BUILD_JOBS concurrent nix builds (~356s each, measured)"
  for r in 1 2 3; do
    est="$(estimate_seconds "$r")"
    printf '  %d rep(s): %-8s %s\n' "$r" "$(fmt_hms "$est")" \
      "$([ "$est" -le "$ceiling" ] && echo fits || echo "OVER ${BUDGET_HOURS}h")"
  done
  echo ""
  echo "max reps inside ${BUDGET_HOURS}h: $(reps_that_fit "$ceiling")"
  echo "paired comparisons at $REPS rep(s): 2-level factors n=$(( $(cell_count) * REPS / 2 ))"
}

cmd_run() {
  local ceiling=$((BUDGET_HOURS * 3600)) est
  est="$(estimate_seconds "$REPS")"
  if [ "$est" -gt "$ceiling" ]; then
    echo "REFUSING: $REPS reps = $(fmt_hms "$est"), over ${BUDGET_HOURS}h." >&2
    echo "Use REPS=$(reps_that_fit "$ceiling") or raise BUDGET_HOURS." >&2
    return 1
  fi
  preflight || return 1

  local csv
  csv="$OUTDIR/latency-$(date +%Y%m%d-%H%M%S).csv"
  echo "rep,nvme,dirty,sched,iolat,cpuw,psi_cpu_us,psi_io_us,psi_io_full_us,psi_mem_us,misses_120hz,misses_60hz,max_stall_ms,wake_p99_us,wake_p999_us,read_p99_us,wakeups,temp_c,builds_alive" > "$csv"

  resolve_load_drvs $(( $(cell_count) * REPS * BUILD_JOBS )) || return 1

  capture_state
  # A signal has to restore AND stop. `trap restore_state INT TERM` did only
  # the first half: restore_state returns, the cell loop carries straight on
  # re-applying settings, and its own RESTORED latch then suppresses the real
  # restore at EXIT. A Ctrl-C therefore left every tunable at the last cell's
  # value, and the next run captured that as its baseline. HUP was not trapped
  # at all, so closing the terminal skipped the restore outright.
  trap on_signal INT TERM HUP QUIT
  trap restore_state EXIT

  echo ""
  echo "estimate: $(fmt_hms "$est") for $REPS rep(s), $(cell_count) cells each"
  echo "output:   $csv"
  echo ""

  local start_ts done_n total rep cell
  start_ts="$(date +%s)"; total=$(($(cell_count) * REPS)); done_n=0

  for rep in $(seq 1 "$REPS"); do
    echo "--- rep $rep of $REPS ---"
    while read -r cell; do
      IFS=: read -r n d s i c <<< "$cell"
      done_n=$((done_n + 1))
      local elapsed remain
      elapsed=$(($(date +%s) - start_ts))
      remain=$((done_n > 1 ? elapsed * (total - done_n) / (done_n - 1) : 0))
      printf '[%2d/%2d] nvme=%-5s dirty=%-4s sched=%-5s iolat=%-3s cpuw=%-3s  eta %s\n' \
        "$done_n" "$total" "$n" "$d" "$s" "$i" "$c" "$(fmt_hms "$remain")"
      run_cell "$n" "$d" "$s" "$i" "$c" "$rep" >> "$csv" ||
        echo "  cell FAILED, continuing" >&2
    done < <(block_cells | shuffle_seeded "$rep")
  done

  [ -n "${SUDO_UID:-}" ] && chown -R "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" "$(dirname "$OUTDIR")" 2>/dev/null
  echo ""
  echo "done in $(fmt_hms $(($(date +%s) - start_ts)))"
  cmd_analyze "$csv"
}

# Paired main effects. Cells differing in ONE factor and identical in all
# others (including repetition) are compared directly, so the spread of those
# differences is real run-to-run noise rather than variance leaked in from the
# other factors. Pooling instead inflates every secondary factor's apparent
# noise floor by whatever the largest effect happens to be.
cmd_analyze() {
  # analyze does not run preflight, so it has to resolve the interpreter for
  # itself or it execs the empty string.
  ensure_python || { echo "no usable python3; set PY3=/path/to/python3" >&2; return 1; }
  local -a csvs=()
  if [ "$#" -gt 0 ]; then csvs=("$@"); else
    # Not `ls -t | head -1`: head exits after one line, SIGPIPEs ls, and
    # pipefail turns that into a failure. The names are
    # latency-YYYYmmdd-HHMMSS.csv, so the shell's lexical glob order is already
    # chronological order.
    local -a found=()
    local f
    for f in "$OUTDIR"/latency-*.csv; do [ -f "$f" ] && found+=("$f"); done
    local latest=""
    [ "${#found[@]}" -gt 0 ] && latest="${found[-1]}"
    [ -n "$latest" ] && csvs=("$latest")
  fi
  [ "${#csvs[@]}" -gt 0 ] && [ -f "${csvs[0]}" ] || { echo "no results file" >&2; return 1; }
  echo ""
  echo "=== ${csvs[*]} ==="
  "$PY3" - "${csvs[@]}" <<'PY'
import csv, itertools, statistics, sys

rows = []
for p in sys.argv[1:]:
    with open(p) as fh:
        rows.extend(csv.DictReader(fh))
if not rows:
    print("no rows"); sys.exit()

bad = [r for r in rows if str(r.get("builds_alive", "1")).strip() in ("0", "")]
if bad:
    print(f"   WARNING: {len(bad)} row(s) had no compiler running at window end;")
    print("   their build finished early so part of the window measured an idle")
    print("   machine. Those rows flatter their arm and are excluded.")
    rows = [r for r in rows if r not in bad]

factors = ["nvme", "dirty", "sched", "iolat", "cpuw"]
metrics = [
    ("psi_io_us", "lower", "desktop microseconds stalled on I/O"),
    ("psi_cpu_us", "lower", "desktop microseconds stalled on CPU"),
    ("psi_mem_us", "lower", "desktop microseconds stalled on memory"),
    ("misses_60hz", "lower", "missed 60Hz frame deadlines"),
    ("max_stall_ms", "lower", "longest single stall"),
    ("wake_p999_us", "lower", "wakeup p99.9"),
]

def num(r, k):
    try: return float(r[k])
    except (ValueError, KeyError, TypeError): return None

for metric, better, label in metrics:
    print(f"\n-- {metric}: {label} ({better} is better)")
    for f in factors:
        levels = sorted({r[f] for r in rows})
        cells = []
        for lv in levels:
            vals = [v for v in (num(r, metric) for r in rows if r[f] == lv) if v is not None]
            if vals:
                cells.append(f"{lv}={statistics.median(vals):.0f}(n={len(vals)})")
        if len(cells) < 2: continue
        print(f"   {f:6s} " + "  ".join(cells))
        others = [g for g in factors if g != f] + ["rep"]
        index = {}
        for r in rows:
            v = num(r, metric)
            if v is None: continue
            index.setdefault(tuple(r[g] for g in others), {})[r[f]] = v
        for a, b in itertools.combinations(levels, 2):
            diffs = [c[a] - c[b] for c in index.values() if a in c and b in c]
            if len(diffs) < 2: continue
            med, sd = statistics.median(diffs), statistics.pstdev(diffs)
            verdict = "RESOLVABLE" if abs(med) > sd else "noise"
            # med is (a - b); do NOT reuse `better` for the display string, it
            # is the metric direction and reassigning it silently flips every
            # comparison after the first.
            if better == "lower":
                winner = b if med > 0 else a
            else:
                winner = a if med > 0 else b
            note = f", {winner} better" if verdict == "RESOLVABLE" else ""
            print(f"          {a} vs {b}: delta={med:+.0f} sd={sd:.0f} n={len(diffs)} -> {verdict}{note}")

# Frame-deadline misses are zero-inflated counts: most cells score 0, so the
# median of the paired differences is structurally 0 and reports "noise" no
# matter how lopsided the totals are. misses_120hz was not even in the list
# above, which hid the largest GUI-relevant effect in the first run: cpuw off
# accounted for 24 of 25 misses. Counts get totals and affected-cell splits.
for metric, label in [
    ("misses_120hz", "missed 120Hz frame deadlines"),
    ("misses_60hz", "missed 60Hz frame deadlines"),
]:
    tot = sum(int(num(r, metric) or 0) for r in rows)
    print(f"\n-- {metric}: {label} -- {tot} total over {len(rows)} cells")
    if tot == 0:
        print("   no cell missed a deadline under any configuration")
        continue
    for f in factors:
        parts = []
        for lv in sorted({r[f] for r in rows}):
            vals = [int(num(r, metric) or 0) for r in rows if r[f] == lv]
            hit = sum(1 for v in vals if v)
            parts.append(f"{lv}={sum(vals)} in {hit}/{len(vals)} cells")
        print(f"   {f:6s} " + "   ".join(parts))

print("\n-- best cells by psi_io_us (desktop I/O stall)")
keyed = {}
for r in rows:
    v = num(r, "psi_io_us")
    if v is not None:
        keyed.setdefault(tuple(r[f] for f in factors), []).append(v)
ranked = sorted((statistics.median(v), k) for k, v in keyed.items())
for med, k in ranked[:5]:
    print(f"   {med:12.0f}us  " + " ".join(f"{f}={lv}" for f, lv in zip(factors, k)))
print("   ...")
for med, k in ranked[-3:]:
    print(f"   {med:12.0f}us  " + " ".join(f"{f}={lv}" for f, lv in zip(factors, k)))
PY
}

# Sourcing guard, so the pure helpers can be unit-tested without running a
# measurement.
if [ -n "${AB_LATENCY_SOURCED:-}" ]; then
  return 0 2>/dev/null || true
fi

case "${1:-}" in
  estimate) cmd_estimate ;;
  run) cmd_run ;;
  analyze) shift; cmd_analyze "$@" ;;
  *)
    echo "usage: ab-latency.sh {estimate|run|analyze [csv...]}" >&2
    echo "env: REPS SETTLE MEASURE BUILD_JOBS BUDGET_HOURS PROBE_USER OUTDIR FLAKE" >&2
    exit 64 ;;
esac
