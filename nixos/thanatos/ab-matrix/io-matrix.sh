#!/usr/bin/env bash
# I/O-bound matrix: adios against kyber, under loads that actually saturate the
# queue.
#
# WHY THIS EXISTS. ab-latency.sh answered "which tuning keeps the desktop usable
# during a big build" and found bfq 13x worse than either survivor, with adios
# and kyber tied on the median. But its load was compile-bound: four Rust builds
# whose disk traffic is incidental, and a probe whose own reads are ~20 KB/s.
# Two questions were therefore left open, and both are decided here:
#
#   - adios vs kyber was a tie under light I/O. Which wins when the queue is
#     genuinely contended, and does the answer depend on the shape of the load?
#   - io.latency measured as noise, and the stated reason was that the desktop's
#     I/O never approaches the 10ms target. That reason is exactly what a heavy
#     I/O load invalidates, so the factor is retested here rather than assumed.
#
# RANKING. Responsiveness first, throughput second, by explicit instruction.
# The analyze pass reports both and never silently trades one for the other:
# where the two disagree it says so and applies the stated rule.
#
# FACTORS
#   nvme     adios | kyber
#   profile  seqread | randrw | fsync      (three shapes, see mk_fio_job)
#   dirty    low (64M/16M) | high (256M/64M)
#   iolat    on (10ms) | off
#
#   2 x 3 x 2 x 2 = 24 cells. REPS=3 by default, which this design can afford
#   because an fio load reaches steady state in seconds where a Rust build
#   needed a 45s ramp. Replication is what ab-latency.sh could not buy.
#
# STRUCTURE, and the flaw it exists to avoid. The load runs as root in
# system.slice; the probe runs as the user in user.slice. Those two slices are
# siblings under the root cgroup, so io.latency set on user.slice has a real
# peer to throttle. The original fio matrix put load and probe in one privileged
# cgroup, which made the iolat factor structurally unmeasurable and produced a
# confident "noise" that meant nothing.
#
# WHAT IS DELIBERATELY NOT TESTED. Sustained sequential WRITE. At this drive's
# rate a 90s window is over 100 GB, and a full matrix of write cells would be
# multiple TB of writes for one afternoon's benchmark. seqread saturates the
# same queue at no endurance cost.
#
# ENDURANCE, MEASURED. A REPS=3 run wrote 1.14 TB, roughly 3x what a naive
# fio-throughput estimate predicts. The gap is write amplification: on this
# filesystem 4K random writes cost 10.8x at the device (fio 34.6 MB/s in, 375.6
# MB/s out) because /home is CoW btrfs with compress-force=zstd:1 on LUKS.
# Budget accordingly; the analyze pass prints both the amplification and the
# run's total so the figure is measured rather than guessed.
set -uo pipefail

# A systemd unit inherits systemd's own default PATH, which on NixOS is two
# entries deep: /bin holds sh, /usr/bin holds env, and the other four
# directories do not exist. Put the system profile in front unconditionally.
PATH="/run/wrappers/bin:/run/current-system/sw/bin:${PATH:-}"
export PATH

readonly NVME_DEV="nvme0n1"
readonly NVME_MAJMIN="259:0"
readonly SCHED_PATH="/sys/block/${NVME_DEV}/queue/scheduler"
readonly USER_SLICE="/sys/fs/cgroup/user.slice"
readonly SYS_SLICE="/sys/fs/cgroup/system.slice"
readonly IOLAT_PATH="${USER_SLICE}/io.latency"
readonly DISKSTATS="/proc/diskstats"

SETTLE="${SETTLE:-15}"      # fio ramp_time; excluded from its own statistics
MEASURE="${MEASURE:-90}"    # fio runtime and probe duration, aligned
REPS="${REPS:-3}"
BUDGET_HOURS="${BUDGET_HOURS:-5}"
PROBE_USER="${PROBE_USER:-michael}"
# Must exceed RAM by enough that the cache cannot answer a whole measurement
# window, not merely exceed it. The first run used 40G against 21G of RAM and
# still served 47% of seqread from cache: fio reported 465 MB/s while the device
# delivered 220. At 80G a 90s window at ~500 MB/s touches 45G, so the reader
# cannot revisit cached data within the window. Cells also drop caches first --
# see run_cell.
WORKSET_GB="${WORKSET_GB:-80}"

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# Only /home, /persist and /nix survive a reboot on this host.
OUTDIR="${OUTDIR:-$REPO_ROOT/.io-matrix/results}"
WORKDIR="${WORKDIR:-$REPO_ROOT/.io-matrix/work}"
FIOFILE="$WORKDIR/fio-workset.bin"
READFILE="$WORKDIR/probe-read.bin"

PY3="${PY3:-}"
FIO="${FIO:-}"

NVME_LEVELS=(adios kyber)
PROFILE_LEVELS=(seqread randrw fsync)
DIRTY_LEVELS=(low high)
IOLAT_LEVELS=(on off)

# ---------------------------------------------------------------------------
# Tool resolution. Neither fio nor python3 is installed in any profile on this
# host, and a systemd unit cannot borrow a devshell's PATH. Resolve both to
# absolute paths in preflight, or fail there rather than at cell 37 of 72.
# ---------------------------------------------------------------------------

resolve_from_nixpkgs() { # <attr> <relative-bin> <gcroot-name>
  local out
  mkdir -p "$WORKDIR" 2>/dev/null || true
  # The `nixpkgs` registry entry is system-scoped and pinned by this flake to a
  # store path, so this resolves with no network, no git and no HOME -- none of
  # which a systemd unit has in the shape a login shell does. --out-link makes
  # it a GC root so a stray collect-garbage cannot pull the tool out mid-run.
  out="$(NIX_REMOTE=daemon nix build "nixpkgs#$1" \
    --out-link "$WORKDIR/$3" --print-out-paths 2>/dev/null)" || return 1
  [ -n "$out" ] && [ -x "$out/$2" ] && { echo "$out/$2"; return 0; }
  return 1
}

resolve_python() {
  local c
  for c in "$PY3" /run/current-system/sw/bin/python3 \
           "/etc/profiles/per-user/${PROBE_USER}/bin/python3" \
           "$(command -v python3 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  resolve_from_nixpkgs python3 bin/python3 python3
}

resolve_fio() {
  local c
  for c in "$FIO" /run/current-system/sw/bin/fio \
           "$(command -v fio 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  resolve_from_nixpkgs fio bin/fio fio
}

ensure_tools() {
  if [ -z "$PY3" ] || [ ! -x "$PY3" ]; then PY3="$(resolve_python)" || return 1; fi
  if [ -z "$FIO" ] || [ ! -x "$FIO" ]; then FIO="$(resolve_fio)" || return 1; fi
  [ -x "$PY3" ] && [ -x "$FIO" ]
}

# ---------------------------------------------------------------------------
# Readings
# ---------------------------------------------------------------------------

psi_total() { # <cgroup-dir> <cpu|io|memory> <some|full>  -> EMPTY when absent
  # Never echo 0 for a missing file: "absent" and "never stalled" are different
  # readings, and conflating them records a perfect score for a broken probe.
  [ -r "$1/$2.pressure" ] || return 0
  awk -v want="$3" '$1 == want {
    for (i = 2; i <= NF; i++) if ($i ~ /^total=/) { sub(/^total=/, "", $i); print $i }
  }' "$1/$2.pressure" 2>/dev/null
}

hwmon_temp() { # <name> -- resolve by NAME, never by hwmonN index, which is
               # assigned in probe order and moves between boots.
  local d n
  for d in /sys/class/hwmon/hwmon*; do
    n="$(cat "$d/name" 2>/dev/null || true)"
    if [ "$n" = "$1" ] && [ -r "$d/temp1_input" ]; then
      awk '{printf "%.1f", $1 / 1000}' "$d/temp1_input"
      return 0
    fi
  done
  echo ""
}

# Device-level ground truth, which fio cannot give: it reports what it asked the
# filesystem for, and /home is compress-force=zstd:1 on LUKS on btrfs, so the
# bytes that reach the queue are not the bytes fio wrote. Fields 6 and 10 of a
# diskstats line (after the 3 name fields) are sectors read and written, 512B
# each regardless of the device's logical block size.
diskstat_sectors() { # <read|write>  -> sectors, or EMPTY
  local col
  case "$1" in
    read) col=6 ;;
    write) col=10 ;;
    *) return 1 ;;
  esac
  awk -v dev="$NVME_DEV" -v c="$col" \
    '$3 == dev { print $c; found = 1 } END { if (!found) exit 1 }' "$DISKSTATS" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Applying a configuration
# ---------------------------------------------------------------------------

apply_nvme() {
  echo "$1" > "$SCHED_PATH" 2>/dev/null || return 1
  grep -qw "\[$1\]" "$SCHED_PATH" || return 1
}

dirty_bytes_for() { # <low|high> -> "<dirty_bytes> <dirty_background_bytes>"
  case "$1" in
    low) echo "67108864 16777216" ;;
    high) echo "268435456 67108864" ;;
    *) return 1 ;;
  esac
}

apply_dirty() {
  local pair
  pair="$(dirty_bytes_for "$1")" || return 1
  # shellcheck disable=SC2086
  set -- $pair
  sysctl -q -w "vm.dirty_bytes=$1" "vm.dirty_background_bytes=$2" 2>/dev/null
}

apply_iolat() {
  case "$1" in
    on) echo "$NVME_MAJMIN target=10000" > "$IOLAT_PATH" 2>/dev/null ;;
    # target=0 removes the entry. Writing nothing would leave the previous
    # cell's throttle in place and silently alias one level onto the other.
    off) echo "$NVME_MAJMIN target=0" > "$IOLAT_PATH" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# The load
# ---------------------------------------------------------------------------

# Three shapes, because "which scheduler is better" has no answer independent of
# what the queue is being asked to do.
#
#   seqread  Bandwidth-bound streaming. Saturates the queue at zero endurance
#            cost, which is why sequential WRITE is absent from this matrix.
#   randrw   4K random 70/30 at depth 32. The shape where a scheduler's
#            reordering either helps or hurts, and where read starvation behind
#            writes shows up.
#   fsync    Small buffered writes with a durable commit every 16. This is the
#            shape that historically produced 534ms stalls here and hung
#            Firefox's Quota Manager until its watchdog killed it.
#
# Buffered, not O_DIRECT, deliberately: /home is compress-force=zstd:1, and
# btrfs silently falls back to buffered for O_DIRECT against compressed inodes,
# so direct=1 would claim a path it does not take. Buffered is also what the
# desktop's own reads and writes actually do. Cache is defeated by size, not by
# a flag -- see WORKSET_GB.
mk_fio_job() { # <profile> <jobfile>
  local common
  common="directory=$WORKDIR
filename=$(basename "$FIOFILE")
size=${WORKSET_GB}G
time_based=1
ramp_time=${SETTLE}
runtime=${MEASURE}
invalidate=1
group_reporting=1
randrepeat=1
randseed=20260818
"
  case "$1" in
    seqread)
      printf '[global]\n%s\n[seqread]\nrw=read\nbs=1M\nioengine=io_uring\niodepth=32\nnumjobs=1\n' \
        "$common" > "$2" ;;
    randrw)
      printf '[global]\n%s\n[randrw]\nrw=randrw\nrwmixread=70\nbs=4k\nioengine=io_uring\niodepth=32\nnumjobs=4\n' \
        "$common" > "$2" ;;
    fsync)
      # psync + fsync_on_close=0 + fsync=16: a durable commit every 16 writes,
      # which is the pattern a database or a browser profile store produces.
      printf '[global]\n%s\n[fsyncwrite]\nrw=write\nbs=64k\nioengine=psync\nfsync=16\nnumjobs=2\n' \
        "$common" > "$2" ;;
    *) return 1 ;;
  esac
}

LOAD_PID=""
LOAD_JSON=""

start_load() { # <profile> <jsonpath>
  local job="$WORKDIR/job-$1.fio"
  mk_fio_job "$1" "$job" || return 1
  LOAD_JSON="$2"
  # In system.slice, as root: a genuine sibling of user.slice, so io.latency set
  # on the desktop has a peer with no target of its own to throttle. This is the
  # structural correction over the first fio matrix.
  systemd-run --scope --quiet --collect --slice=system.slice --unit="io-matrix-load" \
    "$FIO" "$job" --output-format=json --output="$2" >/dev/null 2>&1 &
  LOAD_PID=$!
}

stop_load() {
  [ -n "$LOAD_PID" ] && kill "$LOAD_PID" 2>/dev/null
  LOAD_PID=""
  # systemd-run --scope execs fio as a child, so killing the client is not
  # enough; and a leftover fio would load the next cell.
  pkill -x fio 2>/dev/null || true
  systemctl stop io-matrix-load.scope 2>/dev/null || true
  sleep 2
}

# ---------------------------------------------------------------------------
# Cells
# ---------------------------------------------------------------------------

cell_count() { echo $(( ${#NVME_LEVELS[@]} * ${#PROFILE_LEVELS[@]} \
  * ${#DIRTY_LEVELS[@]} * ${#IOLAT_LEVELS[@]} )); }
cell_seconds() { echo $(( SETTLE + MEASURE + 25 )); }
estimate_seconds() { echo $(( $(cell_count) * $1 * $(cell_seconds) )); }

reps_that_fit() { # <ceiling-seconds>
  local r best=0
  for r in 1 2 3 4 5 6; do
    [ "$(estimate_seconds "$r")" -le "$1" ] && best="$r"
  done
  echo "$best"
}

fmt_hms() { printf '%dh%02dm' $(( $1 / 3600 )) $(( ($1 % 3600) / 60 )); }

block_cells() {
  local n p d i
  for n in "${NVME_LEVELS[@]}"; do
    for p in "${PROFILE_LEVELS[@]}"; do
      for d in "${DIRTY_LEVELS[@]}"; do
        for i in "${IOLAT_LEVELS[@]}"; do
          echo "$n:$p:$d:$i"
        done
      done
    done
  done
}

# Deterministic shuffle: a run has to be reproducible from its seed, and an
# ordered matrix aliases slow thermal drift onto whichever factor varies
# slowest.
shuffle_seeded() { shuf --random-source=<(yes "$1"); }

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

RESTORED=0

capture_state() {
  ORIG_SCHED="$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$SCHED_PATH")"
  ORIG_DIRTY="$(cat /proc/sys/vm/dirty_bytes)"
  ORIG_DIRTY_BG="$(cat /proc/sys/vm/dirty_background_bytes)"
  ORIG_IOLAT="$(cat "$IOLAT_PATH" 2>/dev/null || echo "")"
  echo "captured: sched=$ORIG_SCHED dirty=$ORIG_DIRTY/$ORIG_DIRTY_BG iolat='$ORIG_IOLAT'"
  # A previous aborted run can leave the machine tuned, and this function would
  # then adopt that as "original" and faithfully restore back to it at the end.
  local drift=""
  [ -z "$ORIG_IOLAT" ] || drift="io.latency "
  [ -z "$drift" ] || {
    echo "WARN: baseline is not stock (${drift}already set); a previous run"
    echo "      likely did not restore. The matrix itself is unaffected -- every"
    echo "      cell sets all four factors -- but the final restore returns HERE."
  }
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
    # Empty means io.latency was UNSET, and unset is restored by writing a zero
    # target, not by leaving the last cell's throttle behind.
    echo "$NVME_MAJMIN target=0" > "$IOLAT_PATH" 2>/dev/null
  fi
  echo "  sched:  $(sed -n 's/.*\[\(.*\)\].*/\1/p' "$SCHED_PATH")"
  echo "  dirty:  $(cat /proc/sys/vm/dirty_bytes) / $(cat /proc/sys/vm/dirty_background_bytes)"
  echo "  iolat:  $(cat "$IOLAT_PATH" 2>/dev/null || echo unset)"
}

on_signal() {
  echo "" >&2
  echo "signal received -- restoring and stopping" >&2
  restore_state
  exit 130
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

preflight() {
  local fail=0 d mp c n
  [ "$(id -u)" -eq 0 ] || { echo "FAIL: must run as root" >&2; fail=1; }

  for c in awk cat date dirname findmnt grep mkdir nix pkill readlink sed shuf \
           sleep sort sysctl systemctl systemd-run; do
    command -v "$c" >/dev/null || { echo "FAIL: '$c' not on PATH" >&2; fail=1; }
  done

  mkdir -p "$OUTDIR" "$WORKDIR"
  ensure_tools || {
    echo "FAIL: could not resolve python3 and/or fio. Set PY3=/path and FIO=/path." >&2
    fail=1
  }
  [ -n "$PY3" ] && echo "python3:  $PY3"
  [ -n "$FIO" ] && echo "fio:      $FIO"

  id "$PROBE_USER" >/dev/null 2>&1 || { echo "FAIL: no such user '$PROBE_USER'" >&2; fail=1; }
  [ "$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo 0)" = "1" ] || {
    echo "FAIL: not on AC -- TLP changes governor/boost/ASPM at the transition," >&2
    echo "      which would alias a power-state change onto a factor." >&2; fail=1; }

  for n in "${NVME_LEVELS[@]}"; do
    grep -qw "$n" "$SCHED_PATH" || { echo "FAIL: nvme scheduler '$n' unavailable" >&2; fail=1; }
  done
  [ -w "$IOLAT_PATH" ] || { echo "FAIL: $IOLAT_PATH not writable" >&2; fail=1; }
  for c in cpu io memory; do
    [ -r "$USER_SLICE/$c.pressure" ] || { echo "FAIL: PSI $c unavailable on user.slice" >&2; fail=1; }
  done
  [ -n "$(diskstat_sectors read)" ] || { echo "FAIL: no $DISKSTATS line for $NVME_DEV" >&2; fail=1; }
  [ -n "$(hwmon_temp nvme)" ] || echo "WARN: nvme hwmon not found; drive temp column will be empty" >&2

  for d in "$OUTDIR" "$WORKDIR"; do
    mp="$(findmnt -no TARGET --target "$d" 2>/dev/null)"
    case "$mp" in
      /home | /persist | /nix) ;;
      "") echo "FAIL: cannot resolve mountpoint for $d" >&2; fail=1 ;;
      *) echo "FAIL: $d is on '$mp', wiped on reboot" >&2; fail=1 ;;
    esac
  done

  # Working set larger than RAM, or the page cache answers every read and the
  # scheduler under test never sees a request.
  local ramgb
  ramgb="$(awk '/MemTotal/ { printf "%.0f", $2 / 1048576 }' /proc/meminfo)"
  [ "$WORKSET_GB" -gt "$ramgb" ] || {
    echo "FAIL: WORKSET_GB=$WORKSET_GB does not exceed ${ramgb}G of RAM; the page" >&2
    echo "      cache would absorb the reads and no scheduler would be exercised." >&2
    fail=1
  }
  local freegb
  freegb="$(df -BG --output=avail "$WORKDIR" 2>/dev/null | tail -1 | tr -dc '0-9')"
  [ -n "$freegb" ] && [ "$freegb" -gt $((WORKSET_GB + 20)) ] || {
    echo "FAIL: need >$((WORKSET_GB + 20))G free for the working set, have ${freegb:-?}G" >&2
    fail=1
  }

  if [ ! -f "$FIOFILE" ] || [ "$(stat -c %s "$FIOFILE" 2>/dev/null || echo 0)" -lt \
       $((WORKSET_GB * 1073741824)) ]; then
    echo "creating ${WORKSET_GB}G fio working set (one time, a few minutes)..."
    "$FIO" --name=prep --directory="$WORKDIR" --filename="$(basename "$FIOFILE")" \
      --size="${WORKSET_GB}G" --rw=write --bs=1M --ioengine=psync \
      --create_only=1 --output-format=json --output=/dev/null >/dev/null 2>&1 || {
      echo "FAIL: could not create the fio working set" >&2; fail=1; }
  fi
  if [ ! -f "$READFILE" ]; then
    echo "creating probe read file (512M)..."
    dd if=/dev/urandom of="$READFILE" bs=1M count=512 status=none || fail=1
  fi

  [ -n "${SUDO_UID:-}" ] && chown -R "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" \
    "$(dirname "$OUTDIR")" 2>/dev/null
  return "$fail"
}

# ---------------------------------------------------------------------------
# Measurement
# ---------------------------------------------------------------------------

run_cell() { # nvme profile dirty iolat rep csv
  local nvme="$1" profile="$2" dirty="$3" iolat="$4" rep="$5" csv="$6"

  apply_nvme "$nvme" || { echo "ERROR: cannot select scheduler '$nvme'" >&2; return 1; }
  apply_dirty "$dirty" || { echo "ERROR: cannot set dirty '$dirty'" >&2; return 1; }
  apply_iolat "$iolat" || { echo "ERROR: cannot set iolat '$iolat'" >&2; return 1; }

  # Drop the page cache before every cell. Without this the first cells of a
  # run measure a cold cache and later ones a warm one, which aliases run order
  # onto whatever factor the shuffle happened to vary slowly. Applied to every
  # cell equally, so it cannot bias the comparison in either direction.
  sync
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

  local fiojson="$WORKDIR/fio-out.json"
  rm -f "$fiojson"
  start_load "$profile" "$fiojson" || { echo "ERROR: cannot start load" >&2; return 1; }

  # fio's own ramp_time already excludes this window from ITS statistics; the
  # sleep aligns the PSI and probe windows with the same boundary.
  sleep "$SETTLE"

  local cpu0 io0 iof0 mem0 rd0 wr0
  cpu0="$(psi_total "$USER_SLICE" cpu some)"
  io0="$(psi_total "$USER_SLICE" io some)"
  iof0="$(psi_total "$USER_SLICE" io full)"
  mem0="$(psi_total "$USER_SLICE" memory some)"
  rd0="$(diskstat_sectors read)"; wr0="$(diskstat_sectors write)"
  if [ -z "$cpu0" ] || [ -z "$io0" ] || [ -z "$mem0" ] || [ -z "$rd0" ]; then
    echo "ERROR: baseline counters unreadable (cpu='$cpu0' io='$io0' mem='$mem0' rd='$rd0')" >&2
    stop_load
    return 1
  fi

  # The probe runs in user.slice, as the user. That is what gives io.latency
  # something to protect and makes its effect observable rather than theoretical.
  local probe
  probe="$(systemd-run --scope --quiet --collect \
    --slice=user.slice --uid="$PROBE_USER" \
    "$PY3" "$SCRIPT_DIR/latency-probe.py" "$MEASURE" "$READFILE" 2>/dev/null)"

  local cpu1 io1 iof1 mem1 rd1 wr1 temp
  cpu1="$(psi_total "$USER_SLICE" cpu some)"
  io1="$(psi_total "$USER_SLICE" io some)"
  iof1="$(psi_total "$USER_SLICE" io full)"
  mem1="$(psi_total "$USER_SLICE" memory some)"
  rd1="$(diskstat_sectors read)"; wr1="$(diskstat_sectors write)"
  temp="$(hwmon_temp nvme)"

  # Let fio finish and flush its JSON, then stop anything left over.
  wait "$LOAD_PID" 2>/dev/null || true
  stop_load

  local pcpu pio piof pmem
  pcpu=$((cpu1 - cpu0)); pio=$((io1 - io0)); piof=$((iof1 - iof0)); pmem=$((mem1 - mem0))
  # 512-byte sectors regardless of the device's logical block size.
  local rdmb wrmb
  rdmb=$(( (rd1 - rd0) / 2048 )); wrmb=$(( (wr1 - wr0) / 2048 ))

  "$PY3" "$SCRIPT_DIR/io-matrix-row.py" \
    "$rep" "$nvme" "$profile" "$dirty" "$iolat" \
    "$pcpu" "$pio" "$piof" "$pmem" "$rdmb" "$wrmb" "$temp" \
    "$fiojson" "$probe" >> "$csv"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

CSV_HEADER="rep,nvme,profile,dirty,iolat,psi_cpu_us,psi_io_us,psi_io_full_us,psi_mem_us,dev_read_mb,dev_write_mb,dev_temp_c,fio_read_mbps,fio_write_mbps,fio_read_iops,fio_write_iops,fio_lat_p50_us,fio_lat_p99_us,fio_lat_p999_us,misses_120hz,misses_60hz,max_stall_ms,wake_p99_us,wake_p999_us,read_p99_us,wakeups"

cmd_estimate() {
  local ceiling=$((BUDGET_HOURS * 3600)) r est
  echo "cells per rep:    $(cell_count)  (nvme 2 x profile 3 x dirty 2 x iolat 2)"
  echo "seconds per cell: $(cell_seconds)  (settle $SETTLE + measure $MEASURE + 25 apply/stop)"
  echo "working set:      ${WORKSET_GB}G at $FIOFILE"
  for r in 1 2 3 4; do
    est="$(estimate_seconds "$r")"
    printf '  %d rep(s): %-8s %s\n' "$r" "$(fmt_hms "$est")" \
      "$([ "$est" -le "$ceiling" ] && echo fits || echo "OVER ${BUDGET_HOURS}h")"
  done
  echo ""
  echo "max reps inside ${BUDGET_HOURS}h: $(reps_that_fit "$ceiling")"
  echo "paired comparisons at $REPS rep(s): 2-level factors n=$(( $(cell_count) * REPS / 2 ))"
  echo ""
  echo "endurance: seqread writes nothing. randrw and fsync do, roughly"
  echo "  $(( $(cell_count) * REPS * 2 / 3 )) write-bearing cells x ~${MEASURE}s. Expect a few hundred GB"
  echo "  per full run; the exact figure lands in the dev_write_mb column."
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
  csv="$OUTDIR/io-$(date +%Y%m%d-%H%M%S).csv"
  echo "$CSV_HEADER" > "$csv"

  capture_state
  trap on_signal INT TERM HUP QUIT
  trap restore_state EXIT

  echo ""
  echo "estimate: $(fmt_hms "$est") for $REPS rep(s), $(cell_count) cells each"
  echo "output:   $csv"
  echo ""

  local start_ts done_n total rep cell n p d i elapsed remain
  start_ts="$(date +%s)"; total=$(($(cell_count) * REPS)); done_n=0

  for rep in $(seq 1 "$REPS"); do
    echo "--- rep $rep of $REPS ---"
    while read -r cell; do
      IFS=: read -r n p d i <<< "$cell"
      done_n=$((done_n + 1))
      elapsed=$(( $(date +%s) - start_ts ))
      remain=$(( (total - done_n + 1) * $(cell_seconds) ))
      printf '[%2d/%2d] %-5s %-7s %-4s %-3s  elapsed %s, ~%s left\n' \
        "$done_n" "$total" "$n" "$p" "$d" "$i" "$(fmt_hms "$elapsed")" "$(fmt_hms "$remain")"
      run_cell "$n" "$p" "$d" "$i" "$rep" "$csv" || echo "  cell FAILED, continuing" >&2
    done < <(block_cells | shuffle_seeded "$rep")
  done

  restore_state
  trap - EXIT
  echo ""
  cmd_analyze "$csv"
}

cmd_analyze() {
  ensure_tools || { echo "no usable python3; set PY3=/path/to/python3" >&2; return 1; }
  local -a csvs=()
  if [ "$#" -gt 0 ]; then csvs=("$@"); else
    local -a found=()
    local f
    for f in "$OUTDIR"/io-*.csv; do [ -f "$f" ] && found+=("$f"); done
    [ "${#found[@]}" -gt 0 ] && csvs=("${found[-1]}")
  fi
  [ "${#csvs[@]}" -gt 0 ] && [ -f "${csvs[0]}" ] || { echo "no results file" >&2; return 1; }
  "$PY3" "$SCRIPT_DIR/io-matrix-analyze.py" "${csvs[@]}"
}

[ -n "${IO_MATRIX_SOURCED:-}" ] && return 0

case "${1:-}" in
  estimate) cmd_estimate ;;
  run) cmd_run ;;
  analyze) shift; cmd_analyze "$@" ;;
  *)
    echo "usage: io-matrix.sh {estimate|run|analyze [csv...]}" >&2
    exit 2 ;;
esac
