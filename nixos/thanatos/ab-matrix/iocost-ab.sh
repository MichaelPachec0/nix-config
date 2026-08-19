#!/usr/bin/env bash
# Does blk-iocost fix "an app touches the disk during a build"?
#
# THE SYMPTOM, measured. In ab-latency.sh, restricted to what this machine ran
# at the time (adios, scx_flash, CPUWeight 1000/20), the probe's own 4K read
# p99 during four concurrent nix builds was:
#
#     adios 18979us      kyber 20574us      idle, for scale, ~2696us
#
# So a desktop read that costs 2.7ms on a quiet machine costs 19ms during a
# build -- a 7x tail.
#
# That figure was taken under scx_flash, which has since been dropped for
# EEVDF-BORE (see services.scx in memory.nix). The motivating number is
# therefore from the previous scheduler, but the comparison this harness makes
# is unaffected: both arms run under the same held configuration, and the
# sched-ab run measured read p99 as noise across all three schedulers, so the
# symptom is a property of the I/O path rather than of the CPU scheduler. Frame pacing is already solved by the slice CPUWeights
# (24 of 25 dropped frames went away), and nothing dropped a frame in 72 cells
# of pure I/O load. This read tail is the remaining, and only, I/O-domain
# complaint with evidence behind it.
#
# WHY IOCOST AND NOT THE THINGS ALREADY TRIED.
#
#   nix.daemonIOSchedClass = "idle" is inert: adios.c and kyber-iosched.c
#   contain zero references to ioprio (mq-deadline.c has 18). The only elevator
#   here that honoured it was bfq, which lost by 13x.
#
#   io.latency cannot fire. check_scale_change() in block/blk-iolatency.c skips
#   the peer throttle unless the protected cgroup issued more than 5% of recent
#   I/O; a desktop under a build is three orders of magnitude below that.
#
#   io.max is a hard cap and would slow builds on an idle machine, which is
#   exactly what we are not asking for.
#
#   io.weight (blk-iocost) is proportional and work-conserving: surplus weight
#   is donated to whoever is actually asking, so builds get the whole device
#   when the desktop is quiet and yield when it is not. It is an rq_qos policy
#   sitting ABOVE the elevator, so unlike ioprio it is unaffected by adios.
#
# WHY THIS IS A TEST AND NOT A COMMIT. Two mechanisms that sounded equally
# right -- ioprio and io.latency -- turned out to buy exactly nothing here. The
# cost of finding that out by measurement is a few hours; the cost of finding
# out later is a config nobody can explain.
#
# SHAPE. One factor, two levels, many repetitions. Every other factor is held
# at its decided production value, so this is a deep test of one question
# rather than another wide matrix.
set -uo pipefail

# THIS MUST COME BEFORE SCRIPT_DIR. A systemd unit inherits systemd's own
# default PATH, which on NixOS is two entries deep: /bin holds sh, /usr/bin
# holds env, and the other four directories do not exist. SCRIPT_DIR below
# calls readlink and dirname, so under `systemd-run --unit=` they are not found,
# SCRIPT_DIR comes out empty, and the source of ab-latency.sh -- which carries
# its own copy of this prelude -- never happens. Sourcing it cannot fix a PATH
# that is already needed to reach it.
PATH="/run/wrappers/bin:/run/current-system/sw/bin:${PATH:-}"
export PATH

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# Reuse the validated harness: PSI readers, hwmon-by-name, the nix-build load,
# the probe invocation, capture/restore and the signal traps all come from
# there rather than being reimplemented and re-debugged.
AB_LATENCY_SOURCED=1 . "$SCRIPT_DIR/ab-latency.sh"

# ab-latency.sh's preflight validates ITS OWN factor levels, which are not this
# harness's. This run holds nvme=adios, so adios is the only scheduler it needs
# to exist; inheriting a wider list means failing preflight over an arm that is
# never applied.
NVME_LEVELS=(adios)

# NOT REPS="${REPS:-20}". Sourcing ab-latency.sh above already set REPS=1 via
# its own "${REPS:-1}", so a :- default here can never fire. A distinct
# variable cannot collide.
REPS="${IOCOST_REPS:-20}"
IOCOST_LEVELS=(on off)
IOC_QOS="/sys/fs/cgroup/io.cost.qos"
BORE_SYSCTL_IOC="/proc/sys/kernel/sched_bore"
SCX_STATE_IOC="/sys/kernel/sched_ext/state"
USER_IOW="$USER_SLICE/io.weight"
SYS_IOW="$SYS_SLICE/io.weight"

OUTDIR="${OUTDIR:-$REPO_ROOT/.ab-latency/results}"

# ---------------------------------------------------------------------------
# The factor
# ---------------------------------------------------------------------------

# io.weight only does anything once the controller is enabled for the device:
# blk-iocost.c gates every charge and throttle path on `if (!ioc->enabled ...)`.
# The file is root-only and keyed by MAJ:MIN. ctrl=auto lets the kernel pick
# among its built-in AUTOP_SSD_{QD1,DFL,FAST} models and migrate between them
# every AUTOP_CYCLE_NSEC (10s) as the device proves faster or slower than the
# current guess -- which is why no hand calibration is needed to start.
#
# 259:0 is the physical nvme, not the dm-crypt mapper, for the same reason
# io.latency used it: bio cgroup association survives down through dm (proved
# by user.slice's io.stat carrying a 259:0 line), and 259:0 is where the real
# queue contention is.
apply_iocost() {
  case "$1" in
    on)
      echo "$NVME_MAJMIN enable=1 ctrl=auto" > "$IOC_QOS" 2>/dev/null || return 1
      systemctl set-property --runtime user.slice IOWeight=1000 2>/dev/null || return 1
      systemctl set-property --runtime system.slice IOWeight=20 2>/dev/null || return 1
      ;;
    off)
      systemctl set-property --runtime user.slice IOWeight=100 2>/dev/null || return 1
      systemctl set-property --runtime system.slice IOWeight=100 2>/dev/null || return 1
      echo "$NVME_MAJMIN enable=0" > "$IOC_QOS" 2>/dev/null || return 1
      ;;
    *) return 1 ;;
  esac
  verify_iocost "$1"
}

# Read the state back and require it to match. Both previous I/O levers were
# inert in ways no amount of staring at the config would have revealed, so a
# factor that cannot prove it engaged is not allowed to record a row.
verify_iocost() {
  local want_en want_uw qos uw sw
  case "$1" in
    on)  want_en=1; want_uw=1000 ;;
    off) want_en=0; want_uw=100 ;;
  esac
  qos="$(grep -F "$NVME_MAJMIN " "$IOC_QOS" 2>/dev/null)"
  case "$qos" in
    *"enable=$want_en"*) ;;
    *) echo "  iocost verify FAILED: qos line '$qos' lacks enable=$want_en" >&2; return 1 ;;
  esac
  uw="$(awk '$1 == "default" { print $2 }' "$USER_IOW" 2>/dev/null)"
  sw="$(awk '$1 == "default" { print $2 }' "$SYS_IOW" 2>/dev/null)"
  [ "$uw" = "$want_uw" ] || {
    echo "  iocost verify FAILED: user.slice io.weight=$uw want $want_uw" >&2; return 1; }
  [ "$1" = "off" ] || [ "$sw" = "20" ] || {
    echo "  iocost verify FAILED: system.slice io.weight=$sw want 20" >&2; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Held constant at the decided production configuration
# ---------------------------------------------------------------------------

apply_holds() {
  apply_nvme adios || return 1
  apply_dirty low || return 1
  apply_iolat off || return 1
  apply_cpuw on || return 1
  apply_bore_hold || return 1
}

# EEVDF-BORE, matching what memory.nix now ships.
#
# Deliberately NOT `apply_sched eevdf`, which is ab-latency.sh's helper and runs
# `systemctl stop scx`. services.scx.enable is false now, so on a rebooted
# machine there is no scx unit at all and that stop would fail the hold over a
# unit that is supposed to be absent. What matters is the kernel state, not the
# unit: assert sched_ext is not attached, and only try to stop it if something
# has attached one behind our back.
#
# The sched_bore assertion is the same trap sched-ab.sh exists to avoid. BORE
# governs nothing while sched_ext owns the tasks, so a hold that set the sysctl
# without confirming scx is down would run every cell under whatever scheduler
# happened to be attached while the log claimed bore.
apply_bore_hold() {
  local i
  if [ "$(cat "$SCX_STATE_IOC" 2>/dev/null)" = "enabled" ]; then
    systemctl stop scx 2>/dev/null || true
    for i in $(seq 1 15); do
      [ "$(cat "$SCX_STATE_IOC" 2>/dev/null)" != "enabled" ] && break
      sleep 1
    done
  fi
  [ "$(cat "$SCX_STATE_IOC" 2>/dev/null)" != "enabled" ] || {
    echo "  hold FAILED: sched_ext is attached, so BORE is bypassed" >&2
    return 1
  }
  echo 1 > "$BORE_SYSCTL_IOC" 2>/dev/null || {
    echo "  hold FAILED: cannot write $BORE_SYSCTL_IOC (kernel without BORE?)" >&2
    return 1
  }
  [ "$(cat "$BORE_SYSCTL_IOC" 2>/dev/null)" = "1" ] || {
    echo "  hold FAILED: sched_bore did not take" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Budget
# ---------------------------------------------------------------------------

ioc_cell_count() { echo "${#IOCOST_LEVELS[@]}"; }
ioc_estimate() { echo $(( $(ioc_cell_count) * $1 * $(cell_seconds) )); }

# ---------------------------------------------------------------------------
# State: iocost is not part of ab-latency.sh's capture, so add it
# ---------------------------------------------------------------------------

IOC_RESTORED=0
capture_iocost() {
  ORIG_IOC_QOS="$(grep -F "$NVME_MAJMIN " "$IOC_QOS" 2>/dev/null || echo "")"
  ORIG_IOW_USER="$(awk '$1 == "default" { print $2 }' "$USER_IOW" 2>/dev/null || echo 100)"
  ORIG_IOW_SYS="$(awk '$1 == "default" { print $2 }' "$SYS_IOW" 2>/dev/null || echo 100)"
  echo "captured: iocost qos='$ORIG_IOC_QOS' io.weight user=$ORIG_IOW_USER system=$ORIG_IOW_SYS"
}

restore_iocost() {
  [ "$IOC_RESTORED" -eq 1 ] && return 0
  IOC_RESTORED=1
  systemctl set-property --runtime user.slice "IOWeight=$ORIG_IOW_USER" 2>/dev/null
  systemctl set-property --runtime system.slice "IOWeight=$ORIG_IOW_SYS" 2>/dev/null
  # Nothing configured it before this run, so leave the controller off rather
  # than half-configured.
  [ -n "$ORIG_IOC_QOS" ] || echo "$NVME_MAJMIN enable=0" > "$IOC_QOS" 2>/dev/null
  echo "  iocost: $(grep -F "$NVME_MAJMIN " "$IOC_QOS" 2>/dev/null || echo unset)"
  echo "  io.weight: user=$(cat "$USER_IOW" 2>/dev/null) system=$(cat "$SYS_IOW" 2>/dev/null)"
}

ioc_restore_all() { restore_iocost; restore_state; }
ioc_on_signal() {
  echo "" >&2
  echo "signal received -- restoring and stopping" >&2
  ioc_restore_all
  exit 130
}

# ---------------------------------------------------------------------------
# Preflight additions
# ---------------------------------------------------------------------------

ioc_preflight() {
  local fail=0
  [ -w "$IOC_QOS" ] || {
    echo "FAIL: $IOC_QOS not writable. CONFIG_BLK_CGROUP_IOCOST=y is required" >&2
    echo "      and the io controller must be in the root cgroup.subtree_control." >&2
    fail=1
  }
  [ -r "$USER_IOW" ] || { echo "FAIL: $USER_IOW absent; iocost policy not present" >&2; fail=1; }
  grep -qw io /sys/fs/cgroup/cgroup.subtree_control || {
    echo "FAIL: 'io' not in root cgroup.subtree_control" >&2; fail=1; }
  # The held configuration is EEVDF-BORE, so the sysctl has to exist. uname -r
  # cannot tell you whether it will: the bore and non-bore CachyOS builds report
  # the same release string.
  [ -w "$BORE_SYSCTL_IOC" ] || {
    echo "FAIL: $BORE_SYSCTL_IOC absent; this kernel has no BORE." >&2
    echo "      Booted: $(readlink -f /run/booted-system/kernel 2>/dev/null \
      | sed 's|/bzImage$||; s|.*/||; s|^[a-z0-9]\{32\}-||')" >&2
    fail=1
  }
  return "$fail"
}

# ---------------------------------------------------------------------------
# Cell
# ---------------------------------------------------------------------------

ioc_run_cell() { # <on|off> <rep> <csv>
  local level="$1" rep="$2" csv="$3"

  apply_holds || { echo "ERROR: cannot apply the held configuration" >&2; return 1; }
  apply_iocost "$level" || { echo "ERROR: cannot apply iocost=$level" >&2; return 1; }

  start_load "ioc${rep}-$(date +%s)"
  sleep "$SETTLE"

  local cpu0 io0 iof0 mem0
  cpu0="$(psi_total "$USER_SLICE" cpu some)"
  io0="$(psi_total "$USER_SLICE" io some)"
  iof0="$(psi_total "$USER_SLICE" io full)"
  mem0="$(psi_total "$USER_SLICE" memory some)"
  if [ -z "$cpu0" ] || [ -z "$io0" ] || [ -z "$mem0" ]; then
    echo "ERROR: PSI baseline unreadable" >&2
    stop_load
    return 1
  fi

  local probe
  probe="$(systemd-run --scope --quiet --collect \
    --slice=user.slice --uid="$PROBE_USER" \
    "$PY3" "$SCRIPT_DIR/latency-probe.py" "$MEASURE" "$READFILE" 2>/dev/null)"

  local cpu1 io1 iof1 mem1 temp alive
  cpu1="$(psi_total "$USER_SLICE" cpu some)"
  io1="$(psi_total "$USER_SLICE" io some)"
  iof1="$(psi_total "$USER_SLICE" io full)"
  mem1="$(psi_total "$USER_SLICE" memory some)"
  temp="$(hwmon_temp zenpower)"
  # `pgrep -c` prints 0 AND exits 1 when nothing matches, so `|| echo 0`
  # appended a SECOND 0 and the value became "0\n0". That newline landed
  # mid-row and split every CSV line in two. `|| true` keeps pgrep's own
  # count and swallows only the exit status.
  alive="$(pgrep -c -x rustc 2>/dev/null || true)"
  alive="${alive:-0}"
  stop_load

  "$PY3" "$SCRIPT_DIR/probe-row.py" "$rep" "$level" \
    "$((cpu1 - cpu0))" "$((io1 - io0))" "$((iof1 - iof0))" "$((mem1 - mem0))" \
    "$temp" "$alive" "$probe" >> "$csv"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

IOC_HEADER="rep,iocost,psi_cpu_us,psi_io_us,psi_io_full_us,psi_mem_us,temp_c,builds_alive,misses_120hz,misses_60hz,max_stall_ms,wake_p99_us,wake_p999_us,read_p99_us,wakeups"

ioc_cmd_estimate() {
  local ceiling=$((BUDGET_HOURS * 3600)) r est
  echo "cells per rep:    $(ioc_cell_count)  (iocost on | off; everything else held)"
  echo "seconds per cell: $(cell_seconds)  (settle $SETTLE + measure $MEASURE + 30)"
  echo "held constant:    nvme=adios dirty=low sched=bore cpuw=on iolat=off"
  for r in 10 15 20 30; do
    est="$(ioc_estimate "$r")"
    printf '  %2d rep(s): %-8s %s   (n=%d paired)\n' "$r" "$(fmt_hms "$est")" \
      "$([ "$est" -le "$ceiling" ] && echo fits || echo "OVER ${BUDGET_HOURS}h")" "$r"
  done
}

ioc_cmd_run() {
  local ceiling=$((BUDGET_HOURS * 3600)) est
  est="$(ioc_estimate "$REPS")"
  if [ "$est" -gt "$ceiling" ]; then
    echo "REFUSING: $REPS reps = $(fmt_hms "$est"), over ${BUDGET_HOURS}h." >&2
    return 1
  fi
  preflight || return 1
  ioc_preflight || return 1

  local csv
  csv="$OUTDIR/iocost-$(date +%Y%m%d-%H%M%S).csv"
  echo "$IOC_HEADER" > "$csv"

  resolve_load_drvs $(( $(ioc_cell_count) * REPS * BUILD_JOBS )) || return 1

  capture_state
  capture_iocost
  trap ioc_on_signal INT TERM HUP QUIT
  trap ioc_restore_all EXIT

  echo ""
  echo "estimate: $(fmt_hms "$est") for $REPS rep(s) x $(ioc_cell_count) cells"
  echo "output:   $csv"
  echo ""

  local start_ts done_n total rep level elapsed remain
  start_ts="$(date +%s)"; total=$(( $(ioc_cell_count) * REPS )); done_n=0

  for rep in $(seq 1 "$REPS"); do
    # Alternate which level goes first, so slow thermal or fragmentation drift
    # cannot accumulate onto one arm.
    local -a order
    if [ $((rep % 2)) -eq 1 ]; then order=(on off); else order=(off on); fi
    for level in "${order[@]}"; do
      done_n=$((done_n + 1))
      elapsed=$(( $(date +%s) - start_ts ))
      remain=$(( (total - done_n + 1) * $(cell_seconds) ))
      printf '[%2d/%2d] iocost=%-3s  elapsed %s, ~%s left\n' \
        "$done_n" "$total" "$level" "$(fmt_hms "$elapsed")" "$(fmt_hms "$remain")"
      ioc_run_cell "$level" "$rep" "$csv" || echo "  cell FAILED, continuing" >&2
    done
  done

  ioc_restore_all
  trap - EXIT
  echo ""
  ioc_cmd_analyze "$csv"
}

ioc_cmd_analyze() {
  ensure_python || { echo "no usable python3" >&2; return 1; }
  local -a csvs=()
  if [ "$#" -gt 0 ]; then csvs=("$@"); else
    local -a found=(); local f
    for f in "$OUTDIR"/iocost-*.csv; do [ -f "$f" ] && found+=("$f"); done
    [ "${#found[@]}" -gt 0 ] && csvs=("${found[-1]}")
  fi
  [ "${#csvs[@]}" -gt 0 ] && [ -f "${csvs[0]}" ] || { echo "no results file" >&2; return 1; }
  "$PY3" "$SCRIPT_DIR/iocost-analyze.py" "${csvs[@]}"
}

[ -n "${IOCOST_AB_SOURCED:-}" ] && return 0

case "${1:-}" in
  estimate) ioc_cmd_estimate ;;
  run) ioc_cmd_run ;;
  analyze) shift; ioc_cmd_analyze "$@" ;;
  *)
    echo "usage: iocost-ab.sh {estimate|run|analyze [csv...]}" >&2
    exit 2 ;;
esac
