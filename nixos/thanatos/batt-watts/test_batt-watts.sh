#!/usr/bin/env bash
# Unit tests for batt-watts. Usage: bash test_batt-watts.sh ./batt-watts.sh
set -euo pipefail

target="${1:?usage: test_batt-watts.sh PATH_TO_batt-watts.sh}"
# shellcheck source=/dev/null
BATT_WATTS_LIB_ONLY=1 source "$target"

fails=0
check() {
  local name="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name: want '$want' got '$got'" >&2
    fails=$((fails + 1))
  fi
}

# 1 Wh drained over exactly one hour is 1.00 W.
check "1Wh over 3600s" "1.00" "$(watts_from_delta 1000000 0 3600)"

# The observed baseline: 1.74 Wh over 600 s is 10.44 W.
check "baseline 10.44W" "10.44" "$(watts_from_delta 1740000 0 600)"

# Half a watt-hour over ten minutes is 3.00 W.
check "0.5Wh over 600s" "3.00" "$(watts_from_delta 500000 0 600)"

# Non-zero end value: only the delta matters.
check "delta not absolute" "10.44" "$(watts_from_delta 5000000 3260000 600)"

# Charging (end above start) yields a negative figure rather than nonsense.
check "charging is negative" "-1.00" "$(watts_from_delta 0 1000000 3600)"

# Median of an odd-length list.
check "median odd" "7.10" "$(median_of 6.90 7.10 9.00)"

# Median of an odd-length list given out of order.
check "median unsorted" "7.10" "$(median_of 9.00 6.90 7.10)"

# require_discharging exits 2 when AC is online. Run in a subshell so the
# exit does not kill this test process; guard the subshell with || under
# set -e so a nonzero exit from it does not abort the whole suite.
ac_tmp="$(mktemp -d)"
echo 1 >"$ac_tmp/online"
rc=0
(AC_DIR="$ac_tmp" require_discharging) >/dev/null 2>&1 || rc="$?"
check "require_discharging exits 2 when AC online" "2" "$rc"

# require_discharging returns success when AC is offline.
echo 0 >"$ac_tmp/online"
rc=0
(AC_DIR="$ac_tmp" require_discharging) >/dev/null 2>&1 || rc="$?"
check "require_discharging succeeds when AC offline" "0" "$rc"
rm -rf "$ac_tmp"

if [ "$fails" -gt 0 ]; then
  echo "$fails test(s) failed" >&2
  exit 1
fi
echo "all tests passed"
