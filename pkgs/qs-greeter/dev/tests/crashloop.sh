#!/usr/bin/env bash
# Test crash-loop counting in isolation: no compositor, no quickshell.
# QSG_QS_CMD and QSG_FALLBACK_CMD are test seams the wrapper honors.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
run="$here/../../wrapper/qs-greeter-run.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
total=0
check() {
  local name="$1" got="$2" want="$3"
  total=$((total + 1))
  if [ "$got" = "$want" ]; then pass=$((pass + 1))
  else echo "CRASHLOOP-TEST CASE FAIL: $name got=$got want=$want"; fi
}

export QSG_STATE_DIR="$tmp/run"
export QSG_LOG_DIR="$tmp/log"
export QSG_LOG_KEEP=3
export QSG_LOG_ARGS=""
export QSG_JOURNAL=0
export QSG_THRESHOLD=3
export QSG_WINDOW=120
export QSG_CONFIG="$tmp/fake-config"
export QSG_SESSIONS_DIR="$here/fixtures/wayland-sessions"
export QSG_FILTER=uwsm
export QSG_EXTRA_JSON='[]'
export QSG_SHELLS_JSON='[]'
export QSG_TTY_HINT=2
export QSG_SHOW_LOG=0
export QSG_NOW=1000
export QSG_FALLBACK_CMD="echo FALLBACK-ENGAGED"

# a "crashing" greeter
export QSG_QS_CMD="false"
out1="$("$run" 2>&1)"; check "firstCrashRuns" "$(echo "$out1" | grep -c FALLBACK-ENGAGED)" "0"
out2="$("$run" 2>&1)"; check "secondCrashRuns" "$(echo "$out2" | grep -c FALLBACK-ENGAGED)" "0"
out3="$("$run" 2>&1)"; check "thirdCrashRuns" "$(echo "$out3" | grep -c FALLBACK-ENGAGED)" "0"
out4="$("$run" 2>&1)"; check "fourthEngagesFallback" "$(echo "$out4" | grep -c FALLBACK-ENGAGED)" "1"

# the fallback must NOT exit non-zero: exiting returns control to greetd, which
# restarts sway, which re-enters the loop.
"$run" >/dev/null 2>&1; check "fallbackExitsZero" "$?" "0"

# outside the window, the count ages out
export QSG_NOW=9999
out5="$("$run" 2>&1)"; check "windowExpiry" "$(echo "$out5" | grep -c FALLBACK-ENGAGED)" "0"

# a successful launch truncates the counter
rm -rf "$tmp/run"
export QSG_NOW=2000
export QSG_QS_CMD="true"
"$run" >/dev/null 2>&1
check "successTruncates" "$(wc -l <"$tmp/run/crashes" 2>/dev/null || echo 0)" "0"

# sessions.json is written before the greeter starts
check "sessionsWritten" "$(jq -r '.[0].name' "$tmp/run/sessions.json")" "Hyprland (uwsm-managed)"

# log pruning keeps only QSG_LOG_KEEP files
export QSG_QS_CMD="true"
for i in 1 2 3 4 5; do export QSG_NOW=$((3000 + i)); "$run" >/dev/null 2>&1; done
check "logsPruned" "$(find "$tmp/log" -name 'greeter-*.log' | wc -l)" "3"

if [ "$pass" = "$total" ]; then
  echo "CRASHLOOP-TEST PASS $pass/$total"
else
  echo "CRASHLOOP-TEST FAIL $pass/$total"
  exit 1
fi
