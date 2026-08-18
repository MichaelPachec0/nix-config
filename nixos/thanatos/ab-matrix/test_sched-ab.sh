#!/usr/bin/env bash
# Tests for sched-ab.sh. No root, no tunable touched.
#
# The assertion that matters most is that verify_schedmode REJECTS a bore arm
# while sched_ext is still attached. That is the exact failure this harness
# exists to prevent: BORE governs nothing while scx owns the tasks, so an arm
# that does not check would measure flash and label it bore.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
TARGET="${SCHED_AB_TARGET:-$HERE/sched-ab.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=/dev/null
SCHED_AB_SOURCED=1 . "$TARGET"

fail=0
check() {
  if [ "$2" = "$3" ]; then echo "ok   - $1"
  else echo "FAIL - $1: got '$2' want '$3'"; fail=1; fi
}

check "three arms" "$(sch_cell_count)" "3"
SETTLE=45 MEASURE=210
check "cell seconds inherited" "$(cell_seconds)" "285"
check "15 reps" "$(sch_estimate 15)" "12825"
check "15 reps fits 5h" "$([ "$(sch_estimate 15)" -le 18000 ] && echo yes || echo no)" "yes"
check "20 reps fits 5h" "$([ "$(sch_estimate 20)" -le 18000 ] && echo yes || echo no)" "yes"
check "25 reps does not" "$([ "$(sch_estimate 25)" -le 18000 ] && echo yes || echo no)" "no"
check "fmt_hms" "$(fmt_hms "$(sch_estimate 15)")" "3h33m"

for fn in psi_total hwmon_temp start_load stop_load apply_sched apply_nvme \
          apply_dirty apply_iolat apply_cpuw capture_state restore_state; do
  if declare -F "$fn" >/dev/null; then echo "ok   - inherited $fn"
  else echo "FAIL - missing $fn"; fail=1; fi
done

# Arm rotation: over three repetitions each arm must lead exactly once, or the
# arm that always runs last carries every cell's accumulated heat.
n=3
lead=""
for rep in 1 2 3; do
  lead="$lead${SCHED_LEVELS_AB[$(( (0 + rep - 1) % n ))]} "
done
check "each arm leads exactly once over 3 reps" \
  "$(echo "$lead" | tr ' ' '\n' | grep -c .)" "3"
check "rotation covers every arm" \
  "$(echo "$lead" | tr ' ' '\n' | sort -u | grep -c .)" "3"

# This machine really is on a BORE kernel right now.
check "sched_bore sysctl present" \
  "$([ -e "$BORE_SYSCTL" ] && echo yes || echo no)" "yes"
check "sched_ext state readable" "$([ -r "$SCX_STATE" ] && echo yes || echo no)" "yes"
check "uname cannot distinguish the kernels" "$(uname -r)" "7.1.8-cachyos-lto"
check "but the booted kernel path can" \
  "$(readlink -f /run/booted-system/kernel | grep -c bore)" "1"

# THE test. scx is attached right now, so a bore arm must be refused.
check "verify_schedmode bore is REJECTED while scx is attached" \
  "$(verify_schedmode bore 2>/dev/null && echo accepted || echo rejected)" "rejected"
check "verify_schedmode eevdf is REJECTED while scx is attached" \
  "$(verify_schedmode eevdf 2>/dev/null && echo accepted || echo rejected)" "rejected"
check "verify_schedmode flash is accepted while scx is attached" \
  "$(verify_schedmode flash 2>/dev/null && echo accepted || echo rejected)" "accepted"

ensure_python
check "python3 resolved" "$([ -x "${PY3:-}" ] && echo yes || echo no)" "yes"

row="$("$PY3" "$HERE/probe-row.py" 2 bore 1000 2000 1500 10 88.5 12 \
  '{"wakeups":900,"misses_120hz":3,"misses_60hz":0,"max_stall_ms":4.5,"wake_p50_us":10,"wake_p99_us":900,"wake_p999_us":1620,"reads":30,"read_p99_us":2500}')"
check "row column count matches header" \
  "$(echo "$row" | awk -F, '{print NF}')" \
  "$(echo "$SCH_HEADER" | awk -F, '{print NF}')"
check "arm name carried" "$(echo "$row" | cut -d, -f2)" "bore"
check "wake_p999 lands in the right column" "$(echo "$row" | cut -d, -f13)" "1620"

# Analyzer against a planted result: flash best on wakeups and frames, bore and
# eevdf indistinguishable from each other.
{
  echo "$SCH_HEADER"
  for rep in $(seq 1 12); do
    "$PY3" "$HERE/probe-row.py" "$rep" flash 1000 2000 1500 10 88.5 12 \
      "{\"wakeups\":900,\"misses_120hz\":0,\"misses_60hz\":0,\"max_stall_ms\":2.1,\"wake_p50_us\":10,\"wake_p99_us\":800,\"wake_p999_us\":$((1070 + rep))}"
    # bore and eevdf must OVERLAP, not sit a constant 5us apart. A fixed offset
    # has zero variance, so |median| > sd calls even a trivial difference
    # resolvable; real arms that are genuinely indistinguishable scatter across
    # each other, and that is what the analyzer has to recognise as noise.
    "$PY3" "$HERE/probe-row.py" "$rep" bore 1100 2100 1600 12 88.7 12 \
      "{\"wakeups\":900,\"misses_120hz\":2,\"misses_60hz\":0,\"max_stall_ms\":5.4,\"wake_p50_us\":10,\"wake_p99_us\":820,\"wake_p999_us\":$((1560 + (rep * 37 % 110)))}"
    "$PY3" "$HERE/probe-row.py" "$rep" eevdf 1100 2100 1600 12 88.7 12 \
      "{\"wakeups\":900,\"misses_120hz\":2,\"misses_60hz\":0,\"max_stall_ms\":5.5,\"wake_p50_us\":10,\"wake_p99_us\":820,\"wake_p999_us\":$((1560 + (rep * 53 % 110)))}"
  done
} > "$TMP/planted.csv"

out="$("$PY3" "$HERE/sched-analyze.py" "$TMP/planted.csv" 2>&1)" || {
  echo "FAIL - analyzer crashed"; echo "$out" | tail -12; fail=1; }
check "analyzer sees all three arms" "$(echo "$out" | grep -c 'arms present')" "1"

# Scope to the wakeup-p99.9 block. The fixture plants a difference in several
# metrics, so a bare grep over the whole report matches five times and would
# pass for the wrong reason.
wake="$(echo "$out" | awk '/^-- wakeup p99.9/{f=1; next} /^-- /{f=0} f')"
check "flash wins the wakeup tail against bore" \
  "$(echo "$wake" | grep -c 'bore vs flash: .* -> flash better')" "1"
check "bore vs eevdf is noise on the wakeup tail" \
  "$(echo "$wake" | grep -c 'bore vs eevdf: .* -> noise')" "1"
check "analyzer calls out that BORE did nothing" \
  "$(echo "$out" | grep -c 'BORE is not doing anything measurable')" "1"
check "fewest dropped frames names flash" \
  "$(echo "$out" | grep -c 'Fewest dropped frames: flash')" "1"

# A dead-heat dataset must not crown anyone on frames.
{
  echo "$SCH_HEADER"
  for rep in $(seq 1 6); do
    for lv in flash bore eevdf; do
      "$PY3" "$HERE/probe-row.py" "$rep" "$lv" 1000 2000 1500 10 88.5 12 \
        '{"wakeups":900,"misses_120hz":1,"misses_60hz":0,"max_stall_ms":2.1,"wake_p50_us":10,"wake_p99_us":800,"wake_p999_us":1200}'
    done
  done
} > "$TMP/tie.csv"
out2="$("$PY3" "$HERE/sched-analyze.py" "$TMP/tie.csv" 2>&1)"
check "a tie keeps the incumbent" \
  "$(echo "$out2" | grep -c 'keep the incumbent')" "1"

exit "$fail"
