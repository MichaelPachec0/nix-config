#!/usr/bin/env bash
# Tests for iocost-ab.sh. No root, no tunable touched. The point is that a
# harness whose factor cannot prove it engaged is worse than no harness at all,
# which is the lesson ioprio and io.latency both taught the hard way.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
TARGET="${IOCOST_AB_TARGET:-$HERE/iocost-ab.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=/dev/null
IOCOST_AB_SOURCED=1 . "$TARGET"

fail=0
check() {
  if [ "$2" = "$3" ]; then echo "ok   - $1"
  else echo "FAIL - $1: got '$2' want '$3'"; fail=1; fi
}

check "two cells" "$(ioc_cell_count)" "2"
SETTLE=45 MEASURE=210
check "cell seconds inherited" "$(cell_seconds)" "285"
check "20 reps"  "$(ioc_estimate 20)" "11400"
check "20 reps fits 5h" "$([ "$(ioc_estimate 20)" -le 18000 ] && echo yes || echo no)" "yes"
check "40 reps does not"  "$([ "$(ioc_estimate 40)" -le 18000 ] && echo yes || echo no)" "no"
check "fmt_hms"  "$(fmt_hms "$(ioc_estimate 20)")" "3h10m"

# Helpers must have come across from ab-latency.sh rather than being redefined.
for fn in psi_total hwmon_temp start_load stop_load apply_nvme apply_dirty \
          apply_iolat apply_cpuw apply_sched capture_state restore_state; do
  if declare -F "$fn" >/dev/null; then echo "ok   - inherited $fn"
  else echo "FAIL - missing $fn"; fail=1; fi
done

# The machine really does have the controller this harness depends on.
check "iocost qos file exists" "$([ -e /sys/fs/cgroup/io.cost.qos ] && echo yes || echo no)" "yes"
check "io.weight on user.slice" \
  "$([ -r /sys/fs/cgroup/user.slice/io.weight ] && echo yes || echo no)" "yes"
check "io in root subtree_control" \
  "$(grep -cw io /sys/fs/cgroup/cgroup.subtree_control)" "1"

# verify_iocost must REJECT the current unconfigured state when asked to
# confirm "on". If it passed here it would rubber-stamp an inert factor.
check "verify_iocost on rejects an unconfigured device" \
  "$(verify_iocost on 2>/dev/null && echo accepted || echo rejected)" "rejected"

ensure_python
check "python3 resolved" "$([ -x "${PY3:-}" ] && echo yes || echo no)" "yes"

# Row writer: real probe JSON in, full row out.
row="$("$PY3" "$HERE/probe-row.py" 3 on 1000 2000 1500 10 88.5 12 \
  '{"wakeups":900,"misses_120hz":2,"misses_60hz":0,"max_stall_ms":4.5,"wake_p50_us":10,"wake_p99_us":900,"wake_p999_us":1200,"reads":30,"read_p99_us":2500}')"
check "row column count matches header" \
  "$(echo "$row" | awk -F, '{print NF}')" \
  "$(echo "$IOC_HEADER" | awk -F, '{print NF}')"
check "read_p99 lands in the right column" "$(echo "$row" | cut -d, -f14)" "2500"
check "iocost level carried" "$(echo "$row" | cut -d, -f2)" "on"

# A probe that emitted nothing must blank, never zero.
row2="$("$PY3" "$HERE/probe-row.py" 3 off 1 2 3 4 88.5 12 '')"
check "empty probe blanks rather than zeroes" "$(echo "$row2" | cut -d, -f14)" ""

# Analyzer against a planted effect: 'on' is better by 8000us every repetition.
{
  echo "$IOC_HEADER"
  for rep in $(seq 1 12); do
    "$PY3" "$HERE/probe-row.py" "$rep" on 1000 2000 1500 10 88.5 12 \
      "{\"wakeups\":900,\"misses_120hz\":0,\"misses_60hz\":0,\"max_stall_ms\":2.1,\"wake_p50_us\":10,\"wake_p99_us\":800,\"wake_p999_us\":1080,\"reads\":30,\"read_p99_us\":$((5000 + rep * 20))}"
    "$PY3" "$HERE/probe-row.py" "$rep" off 1100 2100 1600 12 88.7 12 \
      "{\"wakeups\":900,\"misses_120hz\":1,\"misses_60hz\":0,\"max_stall_ms\":2.4,\"wake_p50_us\":10,\"wake_p99_us\":820,\"wake_p999_us\":1090,\"reads\":30,\"read_p99_us\":$((13000 + rep * 20))}"
  done
} > "$TMP/planted.csv"

out="$("$PY3" "$HERE/iocost-analyze.py" "$TMP/planted.csv" 2>&1)" || {
  echo "FAIL - analyzer crashed"; echo "$out" | tail -10; fail=1; }
# Scope this to the PRIMARY block. The fixture plants a difference in the
# secondary metrics too, so a bare grep over the whole report legitimately
# matches six times and would pass for the wrong reason.
prim="$(echo "$out" | awk '/^-- PRIMARY/{f=1} /^-- SECONDARY/{f=0} f')"
check "primary metric resolves to 'on'" "$(echo "$prim" | grep -c 'on better')" "1"
check "primary direction is unanimous" \
  "$(echo "$prim" | grep -c "direction favoured 'on' in 12/12")" "1"
check "analyzer reports the recovery fraction" \
  "$(echo "$out" | grep -c 'of what a quiet machine would give')" "1"
check "analyzer verdict says adopt-if-cost-ok" \
  "$(echo "$out" | grep -c 'resolvably improves the read tail')" "1"

# And it must NOT claim an effect when there is none.
{
  echo "$IOC_HEADER"
  for rep in $(seq 1 12); do
    for lv in on off; do
      "$PY3" "$HERE/probe-row.py" "$rep" "$lv" 1000 2000 1500 10 88.5 12 \
        "{\"wakeups\":900,\"misses_120hz\":0,\"misses_60hz\":0,\"max_stall_ms\":2.1,\"wake_p50_us\":10,\"wake_p99_us\":800,\"wake_p999_us\":1080,\"reads\":30,\"read_p99_us\":$((12000 + (rep * 7 % 5) * 900))}"
    done
  done
} > "$TMP/null.csv"
out2="$("$PY3" "$HERE/iocost-analyze.py" "$TMP/null.csv" 2>&1)"
check "analyzer reports no effect on a null dataset" \
  "$(echo "$out2" | grep -c 'No resolvable effect')" "1"

# builds_alive=0 rows must be dropped, not averaged in.
{
  echo "$IOC_HEADER"
  "$PY3" "$HERE/probe-row.py" 1 on 1 2 3 4 88.5 0 '{"read_p99_us":1}'
  for rep in 1 2 3; do
    for lv in on off; do
      "$PY3" "$HERE/probe-row.py" "$rep" "$lv" 1 2 3 4 88.5 12 '{"read_p99_us":5000}'
    done
  done
} > "$TMP/dead.csv"
out3="$("$PY3" "$HERE/iocost-analyze.py" "$TMP/dead.csv" 2>&1)"
check "rows with no compiler alive are excluded" \
  "$(echo "$out3" | grep -c 'had no compiler running')" "1"


# The environment the run ACTUALLY gets. `systemd-run --unit=` hands the script
# systemd's own default PATH, which on NixOS holds exactly two binaries: /bin/sh
# and /usr/bin/env. Everything else -- readlink, dirname, cat, awk, systemctl,
# nix -- is absent. This harness computes SCRIPT_DIR with readlink and dirname
# BEFORE it can source anything, so a missing prelude here is not a degraded
# run, it is an immediate "command not found" and no run at all.
#
# Running the estimate under `env -i` with that exact PATH is the only check
# that catches it. Testing from an interactive shell cannot: the shell's PATH
# hides the bug completely.
SYSPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if env -i PATH="$SYSPATH" /run/current-system/sw/bin/bash "$TARGET" estimate \
     >"$TMP/sysenv.txt" 2>&1; then
  echo "ok   - runs under systemd's default PATH"
else
  echo "FAIL - dies under systemd's default PATH:"
  sed 's/^/         /' "$TMP/sysenv.txt" | head -5
  fail=1
fi
check "estimate produced real output under systemd's PATH" \
  "$(grep -c 'seconds per cell' "$TMP/sysenv.txt")" "1"


# Every scheduler this harness will ask preflight to validate must actually be
# selectable on this machine. preflight itself needs root, so no test runs it;
# this is the non-root equivalent and it is exactly what was missing when bfq
# was dropped from the kernel and left in a level list.
avail="$(cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null)"
for lv in "${NVME_LEVELS[@]}"; do
  if echo "$avail" | grep -qw "$lv"; then
    echo "ok   - nvme scheduler '$lv' is selectable"
  else
    echo "FAIL - nvme scheduler '$lv' is in NVME_LEVELS but not in '$avail'"
    fail=1
  fi
done


# The row writer must REFUSE a field containing a newline. `pgrep -c` prints 0
# and exits 1 when nothing matches, so `$(pgrep -c ... || echo 0)` produced
# "0\n0" and split every CSV line in two; the analyzer then read the tail halves
# as data and reported arm names of "0", "1" and "5". A corrupt row must fail
# the cell loudly instead of being written.
if "$PY3" "$HERE/probe-row.py" 1 flash 1 2 3 4 88.5 "$(printf '0\n0')" '{}' \
     >/dev/null 2>&1; then
  echo "FAIL - probe-row.py accepted a field containing a newline"
  fail=1
else
  echo "ok   - probe-row.py refuses a field containing a newline"
fi
check "probe-row.py refuses a field containing a comma" \
  "$("$PY3" "$HERE/probe-row.py" 1 flash 1 2 3 4 88.5 '1,2' '{}' >/dev/null 2>&1 \
     && echo accepted || echo rejected)" "rejected"

# And the shell idiom that produced it must now yield exactly one line.
alive="$(pgrep -c -x definitely-no-such-process 2>/dev/null || true)"
alive="${alive:-0}"
check "the pgrep idiom yields a single line" "$(printf '%s' "$alive" | wc -l)" "0"

exit "$fail"
