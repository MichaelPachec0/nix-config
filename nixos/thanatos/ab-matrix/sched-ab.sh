#!/usr/bin/env bash
# scx_flash against EEVDF-BORE, on the kernel that actually has BORE.
#
# WHY THIS EXISTS. ab-latency.sh compared flash against EEVDF and flash won:
# wakeup p99.9 1074us against 1629us, and 3 dropped 120Hz frames against 22.
# But that EEVDF had no BORE in it -- the kernel was linux-cachyos-latest-lto,
# whose source contains no sched_bore at all. BORE's whole claim is exactly the
# thing that comparison measured, interactivity under load, so it deserves the
# same test rather than an assumption in either direction.
#
# THE TRAP THIS HARNESS EXISTS TO AVOID. sched_ext replaces the fair class
# wholesale while a scheduler is attached, and scx_flash takes every task. So
# with scx running, BORE governs nothing: sched_bore can be 1, every burst
# tunable can be set, and not one of them touches a single scheduling decision.
# An arm that sets sched_bore=1 without detaching scx measures flash and
# reports it as BORE. That is the same silently-inert failure that wasted a run
# on ioprio and another on io.latency, so every arm here proves what it claims:
# flash asserts sched_ext is attached AND the ops name contains flash, while
# the two fair-class arms assert sched_ext is DOWN and sched_bore reads the
# value they asked for.
#
# A SECOND TRAP, for whoever reads this later: uname -r cannot tell you which
# kernel is running. linux-cachyos-latest-lto and linux-cachyos-bore-lto both
# report 7.1.8-cachyos-lto. The way to know is
# `readlink -f /run/booted-system/kernel`, or the presence of
# /proc/sys/kernel/sched_bore.
#
# ARMS
#   flash   scx_flash attached; the fair class is bypassed entirely
#   bore    scx stopped, sched_bore=1   -- EEVDF plus BORE
#   eevdf   scx stopped, sched_bore=0   -- EEVDF alone, same kernel
#
# The third arm is not scope creep, it is what makes the comparison valid. The
# existing EEVDF numbers were measured on a DIFFERENT KERNEL, so "bore beats
# eevdf" cannot be claimed against them; eevdf has to be re-measured here, in
# this boot, against the same load. It also separates two different questions
# that would otherwise be one: does detaching scx help, and does BORE help.
#
# SHAPE. One factor, three levels, many repetitions, every other factor held at
# its decided production value. Arm order rotates per repetition so thermal
# drift cannot accumulate on whichever arm always ran first.
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
# the probe invocation, apply_sched's attach/detach waits, capture/restore and
# the signal traps all come from there rather than being rewritten.
AB_LATENCY_SOURCED=1 . "$SCRIPT_DIR/ab-latency.sh"

# ab-latency.sh's preflight validates ITS OWN factor levels, which are not this
# harness's. This run holds nvme=adios, so adios is the only scheduler it needs
# to exist; inheriting a wider list means failing preflight over an arm that is
# never applied.
NVME_LEVELS=(adios)

REPS="${REPS:-15}"
SCHED_LEVELS_AB=(flash bore eevdf)
BORE_SYSCTL="/proc/sys/kernel/sched_bore"
SCX_STATE="/sys/kernel/sched_ext/state"
SCX_OPS="/sys/kernel/sched_ext/root/ops"

OUTDIR="${OUTDIR:-$REPO_ROOT/.ab-latency/results}"

# ---------------------------------------------------------------------------
# The factor
# ---------------------------------------------------------------------------

apply_schedmode() {
  case "$1" in
    flash)
      # sched_bore is left at 1 here on purpose: it is inert while scx owns the
      # tasks, and pinning it to the boot default keeps the arm identical to
      # production rather than inventing a fourth configuration.
      echo 1 > "$BORE_SYSCTL" 2>/dev/null || return 1
      apply_sched flash || return 1
      ;;
    bore)
      apply_sched eevdf || return 1        # detach scx so the fair class governs
      echo 1 > "$BORE_SYSCTL" 2>/dev/null || return 1
      ;;
    eevdf)
      apply_sched eevdf || return 1
      echo 0 > "$BORE_SYSCTL" 2>/dev/null || return 1
      ;;
    *) return 1 ;;
  esac
  verify_schedmode "$1"
}

verify_schedmode() {
  local st ops bore
  st="$(cat "$SCX_STATE" 2>/dev/null)"
  ops="$(cat "$SCX_OPS" 2>/dev/null)"
  bore="$(cat "$BORE_SYSCTL" 2>/dev/null)"
  case "$1" in
    flash)
      [ "$st" = "enabled" ] || {
        echo "  verify FAILED: sched_ext state='$st', wanted enabled" >&2; return 1; }
      case "$ops" in
        *flash*) ;;
        *) echo "  verify FAILED: sched_ext ops='$ops', wanted flash" >&2; return 1 ;;
      esac
      ;;
    bore | eevdf)
      # THE important assertion. If sched_ext is still attached, the fair class
      # is empty and this arm is measuring flash under another name.
      [ "$st" != "enabled" ] || {
        echo "  verify FAILED: sched_ext still attached ('$st'), so BORE is bypassed" >&2
        return 1; }
      local want; [ "$1" = "bore" ] && want=1 || want=0
      [ "$bore" = "$want" ] || {
        echo "  verify FAILED: sched_bore=$bore, wanted $want" >&2; return 1; }
      ;;
  esac
  return 0
}

apply_holds() {
  apply_nvme adios || return 1
  apply_dirty low || return 1
  apply_iolat off || return 1
  apply_cpuw on || return 1
}

# ---------------------------------------------------------------------------
# Budget
# ---------------------------------------------------------------------------

sch_cell_count() { echo "${#SCHED_LEVELS_AB[@]}"; }
sch_estimate() { echo $(( $(sch_cell_count) * $1 * $(cell_seconds) )); }

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

SCH_RESTORED=0
capture_sched() {
  ORIG_BORE="$(cat "$BORE_SYSCTL" 2>/dev/null || echo 1)"
  echo "captured: sched_bore=$ORIG_BORE scx=$(systemctl is-active scx 2>/dev/null)"
  echo "          kernel=$(readlink -f /run/booted-system/kernel 2>/dev/null | sed 's|.*/||;s|/bzImage||')"
}

restore_sched() {
  [ "$SCH_RESTORED" -eq 1 ] && return 0
  SCH_RESTORED=1
  echo "$ORIG_BORE" > "$BORE_SYSCTL" 2>/dev/null
  echo "  sched_bore: $(cat "$BORE_SYSCTL" 2>/dev/null)"
}

sch_restore_all() { restore_sched; restore_state; }
sch_on_signal() {
  echo "" >&2
  echo "signal received -- restoring and stopping" >&2
  sch_restore_all
  exit 130
}

# ---------------------------------------------------------------------------
# Preflight additions
# ---------------------------------------------------------------------------

sch_preflight() {
  local fail=0 k
  [ -w "$BORE_SYSCTL" ] || {
    echo "FAIL: $BORE_SYSCTL absent or unwritable." >&2
    k="$(readlink -f /run/booted-system/kernel 2>/dev/null)"
    echo "      Booted kernel is ${k:-unknown}." >&2
    echo "      Note that uname -r reports 7.1.8-cachyos-lto for BOTH the bore" >&2
    echo "      and the non-bore build, so it cannot be used to tell them apart." >&2
    fail=1
  }
  [ -r "$SCX_STATE" ] || { echo "FAIL: $SCX_STATE absent; no sched_ext" >&2; fail=1; }
  systemctl cat scx >/dev/null 2>&1 || { echo "FAIL: no scx unit to start/stop" >&2; fail=1; }
  return "$fail"
}

# ---------------------------------------------------------------------------
# Cell
# ---------------------------------------------------------------------------

sch_run_cell() { # <level> <rep> <csv>
  local level="$1" rep="$2" csv="$3"

  apply_holds || { echo "ERROR: cannot apply the held configuration" >&2; return 1; }
  apply_schedmode "$level" || { echo "ERROR: cannot apply sched=$level" >&2; return 1; }

  start_load "sch${rep}-$(date +%s)"
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

  # Re-assert the arm AFTER the window. scx can die and be restarted by its own
  # retry logic mid-cell (the attach race is documented in memory.nix), which
  # would silently turn a bore cell into a flash cell partway through.
  verify_schedmode "$level" || {
    echo "  ERROR: arm changed under the measurement; discarding this cell" >&2
    stop_load
    return 1
  }

  local cpu1 io1 iof1 mem1 temp alive
  cpu1="$(psi_total "$USER_SLICE" cpu some)"
  io1="$(psi_total "$USER_SLICE" io some)"
  iof1="$(psi_total "$USER_SLICE" io full)"
  mem1="$(psi_total "$USER_SLICE" memory some)"
  temp="$(hwmon_temp zenpower)"
  alive="$(pgrep -c -x rustc 2>/dev/null || echo 0)"
  stop_load

  "$PY3" "$SCRIPT_DIR/probe-row.py" "$rep" "$level" \
    "$((cpu1 - cpu0))" "$((io1 - io0))" "$((iof1 - iof0))" "$((mem1 - mem0))" \
    "$temp" "$alive" "$probe" >> "$csv"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

SCH_HEADER="rep,sched,psi_cpu_us,psi_io_us,psi_io_full_us,psi_mem_us,temp_c,builds_alive,misses_120hz,misses_60hz,max_stall_ms,wake_p99_us,wake_p999_us,read_p99_us,wakeups"

sch_cmd_estimate() {
  local ceiling=$((BUDGET_HOURS * 3600)) r est
  echo "arms:             ${SCHED_LEVELS_AB[*]}"
  echo "seconds per cell: $(cell_seconds)  (settle $SETTLE + measure $MEASURE + 30)"
  echo "held constant:    nvme=adios dirty=low cpuw=on iolat=off"
  for r in 10 15 20; do
    est="$(sch_estimate "$r")"
    printf '  %2d rep(s): %-8s %s   (n=%d paired per comparison)\n' "$r" "$(fmt_hms "$est")" \
      "$([ "$est" -le "$ceiling" ] && echo fits || echo "OVER ${BUDGET_HOURS}h")" "$r"
  done
}

sch_cmd_run() {
  local ceiling=$((BUDGET_HOURS * 3600)) est
  est="$(sch_estimate "$REPS")"
  if [ "$est" -gt "$ceiling" ]; then
    echo "REFUSING: $REPS reps = $(fmt_hms "$est"), over ${BUDGET_HOURS}h." >&2
    return 1
  fi
  preflight || return 1
  sch_preflight || return 1

  local csv
  csv="$OUTDIR/sched-$(date +%Y%m%d-%H%M%S).csv"
  echo "$SCH_HEADER" > "$csv"

  capture_state
  capture_sched
  trap sch_on_signal INT TERM HUP QUIT
  trap sch_restore_all EXIT

  echo ""
  echo "estimate: $(fmt_hms "$est") for $REPS rep(s) x $(sch_cell_count) arms"
  echo "output:   $csv"
  echo ""

  local start_ts done_n total rep level i n elapsed remain
  start_ts="$(date +%s)"; total=$(( $(sch_cell_count) * REPS )); done_n=0
  n="$(sch_cell_count)"

  for rep in $(seq 1 "$REPS"); do
    # Rotate the starting arm each repetition: with three arms and a fixed
    # order, the arm that always ran last would carry every cell's worth of
    # accumulated heat.
    for i in $(seq 0 $((n - 1))); do
      level="${SCHED_LEVELS_AB[$(( (i + rep - 1) % n ))]}"
      done_n=$((done_n + 1))
      elapsed=$(( $(date +%s) - start_ts ))
      remain=$(( (total - done_n + 1) * $(cell_seconds) ))
      printf '[%2d/%2d] sched=%-5s  elapsed %s, ~%s left\n' \
        "$done_n" "$total" "$level" "$(fmt_hms "$elapsed")" "$(fmt_hms "$remain")"
      sch_run_cell "$level" "$rep" "$csv" || echo "  cell FAILED, continuing" >&2
    done
  done

  sch_restore_all
  trap - EXIT
  echo ""
  sch_cmd_analyze "$csv"
}

sch_cmd_analyze() {
  ensure_python || { echo "no usable python3" >&2; return 1; }
  local -a csvs=()
  if [ "$#" -gt 0 ]; then csvs=("$@"); else
    local -a found=(); local f
    for f in "$OUTDIR"/sched-*.csv; do [ -f "$f" ] && found+=("$f"); done
    [ "${#found[@]}" -gt 0 ] && csvs=("${found[-1]}")
  fi
  [ "${#csvs[@]}" -gt 0 ] && [ -f "${csvs[0]}" ] || { echo "no results file" >&2; return 1; }
  "$PY3" "$SCRIPT_DIR/sched-analyze.py" "${csvs[@]}"
}

[ -n "${SCHED_AB_SOURCED:-}" ] && return 0

case "${1:-}" in
  estimate) sch_cmd_estimate ;;
  run) sch_cmd_run ;;
  analyze) shift; sch_cmd_analyze "$@" ;;
  *)
    echo "usage: sched-ab.sh {estimate|run|analyze [csv...]}" >&2
    exit 2 ;;
esac
