#!/usr/bin/env bash
# Full-factorial matrix benchmark for the CachyOS migration's open tuning
# questions.
#
# WHY A MATRIX AND NOT SIX SEPARATE A/Bs
#
# Six two-arm A/Bs answer six questions in isolation and cannot answer the one
# that matters: whether the best NVMe scheduler is still the best once the
# writeback limit changes, or whether io.latency earns its keep under a
# different CPU scheduler. Interactions between these knobs are exactly what a
# per-knob test is blind to.
#
# A full factorial also buys replication for free. Every cell contributes to
# every factor's main effect, so with 2 repetitions of 48 cells each NVMe
# scheduler level is averaged over 32 runs and each writeback level over 48 --
# far more samples per level than any two-arm test on this machine has ever
# had. That matters here specifically: three separate optimisation ideas on this
# host died because run-to-run variance exceeded the effect, and two more
# produced confident wrong answers from sequential runs.
#
# FACTORS (all runtime-changeable; anything needing a rebuild is out of scope)
#
#   nvme    bfq | kyber | adios        /sys/block/nvme0n1/queue/scheduler
#   dirty   low (64M/16M) | high (256M/64M)   vm.dirty_bytes + _background_
#   zram    200 | 100 (percent of RAM)  swapoff, reset, resize, swapon
#   sched   flash | eevdf               systemctl start/stop scx
#   iolat   on (10ms) | off             user.slice io.latency
#
#   3 x 2 x 2 x 2 x 2 = 48 cells.
#
# DESIGN CHOICES THAT ARE NOT ARBITRARY
#
#   zram is the OUTER block because it is the only factor whose change is
#   disruptive: it needs swapoff, which must page everything currently in zram
#   back out before the device can be reset. Changing it per-cell would be both
#   slow and a source of state carried between cells. It is counterbalanced
#   across repetitions (rep 1 runs 200 then 100, rep 2 runs 100 then 200) so it
#   is not confounded with elapsed time.
#
#   Cell order within a block is SHUFFLED, not sequential. Three hours of
#   sustained load heat-soaks this laptop, and a sequential sweep would alias
#   thermal drift onto whichever factor happened to vary slowest. Package
#   temperature is recorded per cell so drift can be checked rather than
#   assumed.
#
#   The writer is BUFFERED and the reader is DIRECT. That split is what makes
#   the writeback factor observable: buffered writes are what create dirty
#   pages, so vm.dirty_bytes governs when writeback storms; a direct reader then
#   measures the latency those storms inflict without the page cache hiding it.
#
#   Memory ballast runs inside a systemd scope with MemoryHigh, NOT as a bare
#   allocator. Without pressure the zram factor is inert and the run would
#   measure nothing; with a bare allocator, forcing enough pressure to engage
#   zram risks taking the desktop down. A bounded cgroup forces that one cgroup
#   to reclaim into zram while leaving the system's own headroom intact.
#
# METRICS: read latency p50/p99/p99.9, write bandwidth, and a scheduler wakeup
# probe. Deliberately NOT collapsed into one score -- these trade against each
# other and which one matters is the user's call, not this script's.
set -uo pipefail

readonly NVME_DEV="nvme0n1"
readonly NVME_MAJMIN="259:0"
readonly SCHED_PATH="/sys/block/${NVME_DEV}/queue/scheduler"
readonly IOLAT_PATH="/sys/fs/cgroup/user.slice/io.latency"
readonly ZRAM_DEV="/dev/zram0"
readonly ZRAM_SYS="/sys/block/zram0"

# Tunables. Defaults are sized so a 2-rep run lands near 2.75h, comfortably
# inside the 5h ceiling with room for a third rep.
RUNTIME="${RUNTIME:-75}"      # seconds of measurement per cell
SETTLE="${SETTLE:-15}"        # seconds after applying a config, before measuring
REPS="${REPS:-2}"
BALLAST_MB="${BALLAST_MB:-6144}"
BALLAST_HIGH="${BALLAST_HIGH:-2G}"   # MemoryHigh on the ballast scope
TESTDIR="${TESTDIR:-/var/tmp/ab-matrix}"
OUTDIR="${OUTDIR:-/var/tmp/ab-matrix-results}"
BUDGET_HOURS="${BUDGET_HOURS:-5}"

FIO="${FIO:-fio}"

# Levels.
NVME_LEVELS=(bfq kyber adios)
DIRTY_LEVELS=(low high)
ZRAM_LEVELS=(200 100)
SCHED_LEVELS=(flash eevdf)
IOLAT_LEVELS=(on off)

# ---------------------------------------------------------------------------
# Pure helpers (unit-tested; see test_ab-matrix.sh)
# ---------------------------------------------------------------------------

# Total cells for one repetition.
cell_count() {
  echo $((${#NVME_LEVELS[@]} * ${#DIRTY_LEVELS[@]} * ${#SCHED_LEVELS[@]} * ${#IOLAT_LEVELS[@]} * ${#ZRAM_LEVELS[@]}))
}

# Seconds one cell costs, including the fixed overhead of applying a config.
# The 10s constant is the scx stop/start round trip, which dominates setup.
cell_seconds() {
  echo $((RUNTIME + SETTLE + 10))
}

# Whole-run estimate in seconds, including the zram block switches.
# Each rep switches zram twice; a switch costs about a minute.
estimate_seconds() {
  local cells reps
  cells="$(cell_count)"
  reps="$1"
  echo $((cells * reps * $(cell_seconds) + reps * 2 * 60))
}

fmt_hms() {
  local s="$1"
  printf '%dh%02dm' $((s / 3600)) $(((s % 3600) / 60))
}

# Refuses a plan that cannot finish inside the ceiling. Returns the reps that
# DO fit so the caller can suggest one rather than just failing.
reps_that_fit() {
  local ceiling_s="$1" r=0 i
  for i in 1 2 3 4 5 6; do
    if [ "$(estimate_seconds "$i")" -le "$ceiling_s" ]; then r="$i"; fi
  done
  echo "$r"
}

# Deterministic shuffle: same seed gives the same order, so a run can be
# reproduced or resumed without re-randomising into a different design.
# Reads the list on stdin so callers never have to word-split a command
# substitution.
shuffle_seeded() {
  local seed="$1"
  shuf --random-source=<(yes "$seed")
}

# Builds every cell id for one zram block, as nvme:dirty:sched:iolat.
block_cells() {
  local n d s i
  for n in "${NVME_LEVELS[@]}"; do
    for d in "${DIRTY_LEVELS[@]}"; do
      for s in "${SCHED_LEVELS[@]}"; do
        for i in "${IOLAT_LEVELS[@]}"; do
          echo "$n:$d:$s:$i"
        done
      done
    done
  done
}

# Counterbalance zram across reps so it is not confounded with elapsed time.
zram_order_for_rep() {
  local rep="$1"
  if [ $((rep % 2)) -eq 1 ]; then
    echo "${ZRAM_LEVELS[0]} ${ZRAM_LEVELS[1]}"
  else
    echo "${ZRAM_LEVELS[1]} ${ZRAM_LEVELS[0]}"
  fi
}

dirty_bytes_for() {
  case "$1" in
    low) echo "67108864 16777216" ;;
    high) echo "268435456 67108864" ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# State capture and restore
# ---------------------------------------------------------------------------

ORIG_SCHED=""
ORIG_DIRTY=""
ORIG_DIRTY_BG=""
ORIG_IOLAT=""
ORIG_ZRAM_DISKSIZE=""
ORIG_SCX_ACTIVE=""
RESTORED=0

capture_state() {
  ORIG_SCHED="$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$SCHED_PATH")"
  ORIG_DIRTY="$(cat /proc/sys/vm/dirty_bytes)"
  ORIG_DIRTY_BG="$(cat /proc/sys/vm/dirty_background_bytes)"
  ORIG_IOLAT="$(cat "$IOLAT_PATH" 2>/dev/null || echo "")"
  ORIG_ZRAM_DISKSIZE="$(cat "$ZRAM_SYS/disksize")"
  ORIG_SCX_ACTIVE="$(systemctl is-active scx 2>/dev/null || true)"
  echo "captured: sched=$ORIG_SCHED dirty=$ORIG_DIRTY/$ORIG_DIRTY_BG iolat='$ORIG_IOLAT' zram=$ORIG_ZRAM_DISKSIZE scx=$ORIG_SCX_ACTIVE"
}

restore_state() {
  [ "$RESTORED" -eq 1 ] && return 0
  RESTORED=1
  echo ""
  echo "=== restoring original state ==="
  stop_load || true
  [ -n "$ORIG_SCHED" ] && echo "$ORIG_SCHED" > "$SCHED_PATH" 2>/dev/null
  [ -n "$ORIG_DIRTY" ] && sysctl -q -w "vm.dirty_bytes=$ORIG_DIRTY" 2>/dev/null
  [ -n "$ORIG_DIRTY_BG" ] && sysctl -q -w "vm.dirty_background_bytes=$ORIG_DIRTY_BG" 2>/dev/null
  if [ -n "$ORIG_IOLAT" ]; then
    echo "$ORIG_IOLAT" > "$IOLAT_PATH" 2>/dev/null
  fi
  # zram last: it is the slowest and the one most worth getting right.
  local cur
  cur="$(cat "$ZRAM_SYS/disksize")"
  if [ -n "$ORIG_ZRAM_DISKSIZE" ] && [ "$cur" != "$ORIG_ZRAM_DISKSIZE" ]; then
    echo "  restoring zram disksize to $ORIG_ZRAM_DISKSIZE"
    set_zram_bytes "$ORIG_ZRAM_DISKSIZE" || echo "  WARNING: zram restore FAILED, check zramctl"
  fi
  if [ "$ORIG_SCX_ACTIVE" = "active" ]; then
    systemctl start scx 2>/dev/null || true
  else
    systemctl stop scx 2>/dev/null || true
  fi
  echo "=== restored ==="
  verify_state
}

verify_state() {
  echo "  sched:  $(sed -n 's/.*\[\(.*\)\].*/\1/p' "$SCHED_PATH")"
  echo "  dirty:  $(cat /proc/sys/vm/dirty_bytes) / $(cat /proc/sys/vm/dirty_background_bytes)"
  echo "  iolat:  $(cat "$IOLAT_PATH" 2>/dev/null || echo unset)"
  echo "  zram:   $(cat "$ZRAM_SYS/disksize")"
  echo "  scx:    $(systemctl is-active scx 2>/dev/null || echo inactive)"
}

# ---------------------------------------------------------------------------
# Applying a configuration
# ---------------------------------------------------------------------------

apply_nvme() {
  echo "$1" > "$SCHED_PATH" || return 1
  local got
  got="$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$SCHED_PATH")"
  [ "$got" = "$1" ] || {
    echo "ERROR: nvme scheduler is '$got', wanted '$1'" >&2
    return 1
  }
}

apply_dirty() {
  local pair
  pair="$(dirty_bytes_for "$1")" || return 1
  # Order matters only in that both must be written; writing either *_bytes
  # zeroes the matching *_ratio, which is intended here.
  sysctl -q -w "vm.dirty_bytes=${pair% *}" "vm.dirty_background_bytes=${pair#* }"
}

apply_iolat() {
  case "$1" in
    on) echo "$NVME_MAJMIN target=10000" > "$IOLAT_PATH" ;;
    off) echo "$NVME_MAJMIN target=0" > "$IOLAT_PATH" ;;
    *) return 1 ;;
  esac
}

apply_sched() {
  case "$1" in
    flash)
      systemctl start scx || return 1
      # Attaching sched_ext is racy by design -- it walks every task and cgroup
      # and any concurrent task creation can make an allocation fail. Poll
      # rather than assume, and give it the same kind of patience the unit
      # override does.
      local i
      for i in $(seq 1 20); do
        [ "$(cat /sys/kernel/sched_ext/state 2>/dev/null)" = "enabled" ] && return 0
        sleep 1
      done
      echo "ERROR: scx did not attach within 20s" >&2
      return 1
      ;;
    eevdf)
      systemctl stop scx || return 1
      local i
      for i in $(seq 1 15); do
        [ "$(cat /sys/kernel/sched_ext/state 2>/dev/null)" != "enabled" ] && return 0
        sleep 1
      done
      echo "ERROR: sched_ext still attached after stop" >&2
      return 1
      ;;
    *) return 1 ;;
  esac
}

# zram resize. The dangerous one, hence the guards.
set_zram_bytes() {
  local want="$1" data_bytes avail_kb
  # swapoff has to relocate whatever zram currently holds. With a 50G disk swap
  # behind it that is survivable but slow, and if RAM is tight it is not
  # survivable at all. Refuse rather than gamble.
  data_bytes="$(cat "$ZRAM_SYS/mm_stat" 2>/dev/null | awk '{print $1}')"
  data_bytes="${data_bytes:-0}"
  avail_kb="$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
  if [ "$data_bytes" -gt $((4 * 1024 * 1024 * 1024)) ]; then
    echo "  zram holds $((data_bytes / 1024 / 1024))MB; waiting for it to drain" >&2
    sleep 30
  fi
  if [ "$avail_kb" -lt $((2 * 1024 * 1024)) ]; then
    echo "ERROR: only $((avail_kb / 1024))MB available; refusing to swapoff zram" >&2
    return 1
  fi
  swapoff "$ZRAM_DEV" || {
    echo "ERROR: swapoff $ZRAM_DEV failed" >&2
    return 1
  }
  echo 1 > "$ZRAM_SYS/reset"
  echo "$want" > "$ZRAM_SYS/disksize"
  mkswap "$ZRAM_DEV" >/dev/null 2>&1
  # Priority 100 matches the configured value; the disk swap sits at -1 and
  # must stay lower or the whole tiering inverts.
  swapon -p 100 "$ZRAM_DEV" || {
    echo "ERROR: swapon $ZRAM_DEV failed" >&2
    return 1
  }
}

apply_zram() {
  local pct="$1" ramkb bytes
  ramkb="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
  bytes=$((ramkb * 1024 / 100 * pct))
  set_zram_bytes "$bytes"
}

# ---------------------------------------------------------------------------
# Load generation
# ---------------------------------------------------------------------------

BALLAST_UNIT="ab-matrix-ballast"
CPU_PIDS=()

start_load() {
  # Memory ballast inside a bounded scope. MemoryHigh forces THIS cgroup to
  # reclaim -- which is what pushes pages into zram -- without putting the
  # desktop or the system slice at risk.
  systemd-run --unit="$BALLAST_UNIT" --scope --quiet \
    -p MemoryHigh="$BALLAST_HIGH" -p MemoryMax=$((BALLAST_MB * 2))M \
    -p MemoryLow=0 -p ManagedOOMPreference=avoid \
    python3 -c "
import time
mb = $BALLAST_MB
chunk = bytearray(1024*1024)
blocks = [bytearray(chunk) for _ in range(mb)]
# Touch continuously so pages stay hot enough to be re-faulted from zram
# rather than simply sitting there compressed and idle.
i = 0
while True:
    b = blocks[i % len(blocks)]
    b[0] = (b[0] + 1) % 251
    b[len(b)//2] = b[0]
    i += 1
    if i % 4096 == 0:
        time.sleep(0.001)
" >/dev/null 2>&1 &

  # CPU load, so the scheduler factor has something to schedule. Half the
  # threads, leaving room for the probe and for fio itself; a fully saturated
  # machine measures queueing, not scheduling.
  local n
  n=$(($(nproc) / 2))
  local i
  for i in $(seq 1 "$n"); do
    (while :; do :; done) &
    CPU_PIDS+=($!)
  done
}

stop_load() {
  local p
  for p in "${CPU_PIDS[@]:-}"; do
    [ -n "$p" ] && kill "$p" 2>/dev/null
  done
  CPU_PIDS=()
  systemctl stop "${BALLAST_UNIT}.scope" 2>/dev/null || true
  pkill -f 'ab-matrix-ballast' 2>/dev/null || true
}

# Scheduler wakeup probe: sleep for a fixed interval and record how late the
# wakeup actually was. This is the metric the CPU-scheduler factor moves; read
# latency is IO-bound and would barely notice it.
wakeup_probe() {
  local secs="$1"
  python3 -c "
import time, sys
end = time.monotonic() + $secs
d = []
while time.monotonic() < end:
    t0 = time.monotonic()
    time.sleep(0.001)
    d.append((time.monotonic() - t0 - 0.001) * 1e6)
d.sort()
if not d:
    print('0 0'); sys.exit()
p50 = d[len(d)//2]
p99 = d[min(len(d)-1, int(len(d)*0.99))]
print('%.1f %.1f' % (p50, p99))
"
}

# ---------------------------------------------------------------------------
# Measurement
# ---------------------------------------------------------------------------

make_fio_job() {
  cat > "$TESTDIR/job.fio" <<EOF
[global]
directory=$TESTDIR
ioengine=psync
runtime=$RUNTIME
time_based=1
group_reporting=0
randrepeat=1
allrandrepeat=1

# Buffered on purpose: buffered writes are what create dirty pages, which is
# the only way vm.dirty_bytes becomes observable.
[writer]
rw=write
bs=1M
size=4G
numjobs=1
direct=0
fsync_on_close=0

# Direct on purpose: the page cache would otherwise absorb the very stalls
# this is trying to measure.
[reader]
rw=randread
bs=4k
size=2G
numjobs=1
direct=1
EOF
}

run_cell() {
  local nvme="$1" dirty="$2" zram="$3" sched="$4" iolat="$5" rep="$6"
  local json temp wake

  apply_nvme "$nvme" || return 1
  apply_dirty "$dirty" || return 1
  apply_iolat "$iolat" || return 1
  apply_sched "$sched" || return 1

  start_load
  sleep "$SETTLE"

  json="$TESTDIR/out.json"
  "$FIO" --output-format=json --output="$json" "$TESTDIR/job.fio" >/dev/null 2>&1 &
  local fio_pid=$!

  # Probe while fio runs, so the wakeup number describes the same moment the
  # IO numbers do.
  sleep 5
  wake="$(wakeup_probe $((RUNTIME - 15)))"
  wait "$fio_pid"

  temp="$(awk '{printf "%.1f", $1/1000}' /sys/class/hwmon/hwmon3/temp1_input 2>/dev/null || echo 0)"
  local zdata
  zdata="$(awk '{printf "%.0f", $1/1024/1024}' "$ZRAM_SYS/mm_stat" 2>/dev/null || echo 0)"

  stop_load

  # fio reports clat in nanoseconds for these engines; normalise to us.
  local r_p50 r_p99 r_p999 w_bw
  r_p50="$(jq -r '[.jobs[]|select(.jobname=="reader")][0].read.clat_ns.percentile."50.000000" // 0' "$json")"
  r_p99="$(jq -r '[.jobs[]|select(.jobname=="reader")][0].read.clat_ns.percentile."99.000000" // 0' "$json")"
  r_p999="$(jq -r '[.jobs[]|select(.jobname=="reader")][0].read.clat_ns.percentile."99.900000" // 0' "$json")"
  w_bw="$(jq -r '[.jobs[]|select(.jobname=="writer")][0].write.bw // 0' "$json")"

  printf '%s,%s,%s,%s,%s,%s,%.1f,%.1f,%.1f,%.1f,%s,%s,%s,%s\n' \
    "$rep" "$zram" "$nvme" "$dirty" "$sched" "$iolat" \
    "$(awk -v v="$r_p50" 'BEGIN{print v/1000}')" \
    "$(awk -v v="$r_p99" 'BEGIN{print v/1000}')" \
    "$(awk -v v="$r_p999" 'BEGIN{print v/1000}')" \
    "$(awk -v v="$w_bw" 'BEGIN{print v/1024}')" \
    "${wake% *}" "${wake#* }" "$temp" "$zdata"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

preflight() {
  local fail=0
  [ "$(id -u)" -eq 0 ] || {
    echo "FAIL: must run as root (every knob here is a root-only sysfs write)" >&2
    fail=1
  }
  command -v "$FIO" >/dev/null || {
    echo "FAIL: fio not found. Pass FIO=/nix/store/.../bin/fio or run inside 'nix shell nixpkgs#fio'" >&2
    fail=1
  }
  command -v jq >/dev/null || {
    echo "FAIL: jq not found" >&2
    fail=1
  }
  # AC only. On battery the discharge curve and the thermal envelope both drift
  # under three hours of load, and TLP switches the governor out from under the
  # test at the transition.
  if [ "$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo 0)" != "1" ]; then
    echo "FAIL: not on AC. This test must not run on battery -- TLP changes the" >&2
    echo "      governor, boost and ASPM at the transition, which would alias a" >&2
    echo "      power-state change onto whichever factor happened to be varying." >&2
    fail=1
  fi
  local n
  for n in "${NVME_LEVELS[@]}"; do
    grep -qw "$n" "$SCHED_PATH" || {
      echo "FAIL: nvme scheduler '$n' not available on this kernel" >&2
      fail=1
    }
  done
  [ -w "$IOLAT_PATH" ] || {
    echo "FAIL: $IOLAT_PATH not writable" >&2
    fail=1
  }
  mkdir -p "$TESTDIR" "$OUTDIR"
  local free_g
  free_g="$(df -BG --output=avail "$TESTDIR" | tail -1 | tr -dc '0-9')"
  [ "$free_g" -ge 20 ] || {
    echo "FAIL: need 20G free in $TESTDIR, have ${free_g}G" >&2
    fail=1
  }
  return "$fail"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

cmd_estimate() {
  local cells est ceiling fits
  cells="$(cell_count)"
  ceiling=$((BUDGET_HOURS * 3600))
  echo "cells per rep:      $cells  (nvme 3 x dirty 2 x zram 2 x sched 2 x iolat 2)"
  echo "seconds per cell:   $(cell_seconds)  (runtime $RUNTIME + settle $SETTLE + 10 setup)"
  local r
  for r in 1 2 3 4; do
    est="$(estimate_seconds "$r")"
    printf '  %d rep(s): %-8s  %s\n' "$r" "$(fmt_hms "$est")" \
      "$([ "$est" -le "$ceiling" ] && echo "fits" || echo "OVER ${BUDGET_HOURS}h")"
  done
  fits="$(reps_that_fit "$ceiling")"
  echo ""
  echo "max reps inside ${BUDGET_HOURS}h: $fits"
  echo "samples per level at $REPS reps: nvme=$((cells * REPS / 3)) dirty=$((cells * REPS / 2))"
}

cmd_run() {
  local est ceiling
  ceiling=$((BUDGET_HOURS * 3600))
  est="$(estimate_seconds "$REPS")"
  if [ "$est" -gt "$ceiling" ]; then
    echo "REFUSING: $REPS reps estimates at $(fmt_hms "$est"), over the ${BUDGET_HOURS}h ceiling." >&2
    echo "Use REPS=$(reps_that_fit "$ceiling") or raise BUDGET_HOURS." >&2
    return 1
  fi
  preflight || return 1

  local csv
  csv="$OUTDIR/matrix-$(date +%Y%m%d-%H%M%S).csv"
  echo "rep,zram,nvme,dirty,sched,iolat,read_p50_us,read_p99_us,read_p999_us,write_bw_mbs,wake_p50_us,wake_p99_us,temp_c,zram_data_mb" > "$csv"

  capture_state
  trap restore_state EXIT INT TERM
  make_fio_job

  echo ""
  echo "estimate: $(fmt_hms "$est") for $REPS rep(s), $(cell_count) cells each"
  echo "output:   $csv"
  echo ""

  local start_ts done_n total
  start_ts="$(date +%s)"
  total=$(($(cell_count) * REPS))
  done_n=0

  local rep zlevel cell
  for rep in $(seq 1 "$REPS"); do
    for zlevel in $(zram_order_for_rep "$rep"); do
      echo "--- rep $rep, zram ${zlevel}% ---"
      apply_zram "$zlevel" || {
        echo "ERROR: could not set zram to ${zlevel}%, skipping this block" >&2
        continue
      }
      # Seed varies per rep and block so the two reps are not the same order,
      # but the whole run is still reproducible from the seed.
      local seed="${rep}${zlevel}"
      while read -r cell; do
        IFS=: read -r n d s i <<< "$cell"
        done_n=$((done_n + 1))
        local elapsed remain
        elapsed=$(($(date +%s) - start_ts))
        remain=$((done_n > 0 ? elapsed * (total - done_n) / done_n : 0))
        printf '[%2d/%2d] zram=%s nvme=%-5s dirty=%-4s sched=%-5s iolat=%-3s  eta %s\n' \
          "$done_n" "$total" "$zlevel" "$n" "$d" "$s" "$i" "$(fmt_hms "$remain")"
        run_cell "$n" "$d" "$zlevel" "$s" "$i" "$rep" >> "$csv" || \
          echo "  cell FAILED, continuing" >&2
      done < <(block_cells | shuffle_seeded "$seed")
    done
  done

  echo ""
  echo "done in $(fmt_hms $(($(date +%s) - start_ts)))"
  echo "results: $csv"
  cmd_analyze "$csv"
}

# Main effects, computed PAIRED.
#
# The naive version of this -- pool every row at a level and compare the pooled
# medians against the pooled spread -- is wrong in a factorial, and wrong in the
# direction that hides results. The spread at a level includes the variance
# contributed by every OTHER factor, so if one factor has a large effect it
# inflates the apparent noise of all the others and they all get reported as
# "noise" no matter how real they are. Verified on synthetic data: a planted
# 580us NVMe effect pushed the reported noise floor for every other factor from
# ~60us to ~256us, which would have buried any writeback effect smaller than
# that.
#
# Instead, compare cells that differ in ONE factor and are otherwise identical,
# including the repetition they came from. The difference within such a pair
# cancels every other factor exactly, so the spread of those differences is
# real run-to-run noise and nothing else.
cmd_analyze() {
  local csv="${1:-}"
  [ -n "$csv" ] || {
    csv="$(ls -t "$OUTDIR"/matrix-*.csv 2>/dev/null | head -1)"
  }
  [ -f "$csv" ] || {
    echo "no results file" >&2
    return 1
  }
  echo ""
  echo "=== main effects from $csv ==="
  python3 - "$csv" <<'PY'
import csv, statistics, sys, itertools

rows = list(csv.DictReader(open(sys.argv[1])))
if not rows:
    print("no rows"); sys.exit()

factors = ["nvme", "dirty", "zram", "sched", "iolat"]
metrics = [("read_p99_us", "lower"), ("read_p50_us", "lower"),
           ("wake_p99_us", "lower"), ("write_bw_mbs", "higher")]

def num(r, k):
    try: return float(r[k])
    except (ValueError, KeyError): return None

for metric, better in metrics:
    print(f"\n-- {metric} ({better} is better)")
    for f in factors:
        levels = sorted({r[f] for r in rows})
        stats = []
        for lv in levels:
            vals = [num(r, metric) for r in rows if r[f] == lv]
            vals = [v for v in vals if v is not None]
            if not vals: continue
            stats.append((lv, statistics.median(vals),
                          statistics.pstdev(vals) if len(vals) > 1 else 0.0,
                          len(vals)))
        if len(stats) < 2: continue
        cells = "  ".join(f"{lv}={med:.1f}(n={n})" for lv, med, sd, n in stats)
        print(f"   {f:6s} {cells}")

        # Paired comparison: index every row by the other factors plus its
        # repetition, so a pair differs in this factor and nothing else.
        others = [g for g in factors if g != f] + ["rep"]
        index = {}
        for r in rows:
            v = num(r, metric)
            if v is None: continue
            index.setdefault(tuple(r[g] for g in others), {})[r[f]] = v
        for a, b in itertools.combinations(levels, 2):
            diffs = [cell[a] - cell[b] for cell in index.values()
                     if a in cell and b in cell]
            if len(diffs) < 2: continue
            med = statistics.median(diffs)
            sd = statistics.pstdev(diffs)
            # A paired effect is real when the typical difference is larger
            # than the spread of those differences. Same bar as everywhere
            # else in this repo: effect must exceed noise, not merely exist.
            verdict = "RESOLVABLE" if abs(med) > sd else "noise"
            # med is (a - b). For a lower-is-better metric a positive delta
            # means b won; for a higher-is-better one it means a won.
            # NOTE the variable name: do NOT reuse `better` here. It is the
            # metric's direction from the enclosing loop, and assigning the
            # display string to it silently flips every comparison after the
            # first from lower-is-better to higher-is-better.
            if better == "lower":
                winner = b if med > 0 else a
            else:
                winner = a if med > 0 else b
            note = f", {winner} better" if verdict == "RESOLVABLE" else ""
            print(f"          {a} vs {b}: paired delta={med:+.1f} sd={sd:.1f} "
                  f"n={len(diffs)} -> {verdict}{note}")

# The reason this is a matrix and not six A/Bs: report the best cell outright,
# and flag when it disagrees with stacking the per-factor winners.
print("\n-- best individual cells by read_p99_us")
keyed = {}
for r in rows:
    k = tuple(r[f] for f in factors)
    v = num(r, "read_p99_us")
    if v is not None:
        keyed.setdefault(k, []).append(v)
ranked = sorted(((statistics.median(v), k) for k, v in keyed.items()))
for med, k in ranked[:5]:
    print(f"   {med:8.1f}us  " + " ".join(f"{f}={lv}" for f, lv in zip(factors, k)))
print("   ...")
for med, k in ranked[-3:]:
    print(f"   {med:8.1f}us  " + " ".join(f"{f}={lv}" for f, lv in zip(factors, k)))
PY
}

case "${1:-}" in
  estimate) cmd_estimate ;;
  run) cmd_run ;;
  analyze) shift; cmd_analyze "${1:-}" ;;
  *)
    echo "usage: ab-matrix.sh {estimate|run|analyze [csv]}" >&2
    echo "env: REPS RUNTIME SETTLE BUDGET_HOURS BALLAST_MB TESTDIR OUTDIR FIO" >&2
    exit 64
    ;;
esac
