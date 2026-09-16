#!/usr/bin/env bash
# Headless red/green check for LockContext's auth timeout. Points a real
# PamContext at a hand-written PAM service that blocks far longer than the
# timeout, and asserts:
#  1. the context re-arms itself instead of hanging (the timeout fires on
#     total PAM silence);
#  2. no late completion for the aborted attempt double-counts a failure
#     during a watch window right after re-arm;
#  3. the context is actually usable again -- a second, independent attempt
#     against a fast service reaches a clean completion, proving abort() did
#     not orphan the worker/pipe for the next attempt;
#  4. a worker that is still emitting PAM messages (a u2f touch cue, a
#     prompt) resets the deadline instead of being aborted mid-conversation
#     -- the timeout is a silent-worker detector, not a wall-clock cap.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pam_exec="$(find /nix/store -maxdepth 5 -name pam_exec.so -print -quit 2>/dev/null)"
pam_echo="$(find /nix/store -maxdepth 5 -name pam_echo.so -print -quit 2>/dev/null)"
sleep_bin="$(command -v sleep)"
false_bin="$(command -v false)"
[ -n "$pam_exec" ] || { echo "pam_exec.so not found"; exit 2; }
[ -n "$pam_echo" ] || { echo "pam_echo.so not found"; exit 2; }

cat > "$tmp/hang" <<EOF
auth required $pam_exec $sleep_bin 60
EOF

# Instant-fail service for the second attempt: exits nonzero immediately, so
# PamContext.onCompleted fires fast (well under authTimeout's interval),
# proving the second attempt was not itself blocked or wedged.
cat > "$tmp/quick" <<EOF
auth required $pam_exec $false_bin
EOF

# Reset-on-message probe: quiet for 1s, then a real PAM conversation message
# (pam_echo.so, standing in for a u2f touch cue), then quiet again for far
# longer than the test's 2000ms authTimeoutMs. If onPamMessage restarts
# authTimeout, the timeout fires ~1s+authTimeoutMs after the message, not at
# the raw authTimeoutMs mark from tryUnlock() -- a measurable, robust (about
# 1s) timing difference that the harness checks in lockctx-timeout-test.qml.
cat > "$tmp/touch-cue.txt" <<EOF
touch your security key
EOF
cat > "$tmp/livehang" <<EOF
auth required $pam_exec $sleep_bin 1
auth optional $pam_echo file=$tmp/touch-cue.txt
auth required $pam_exec $sleep_bin 5
EOF

log="$tmp/out.log"
# qs needs a live Wayland connection to initialize its Qt platform plugin;
# a bare shell (this harness's own invocation context) may not inherit one
# from the graphical session, so fall back to the known live socket.
QS_TEST_PAM_DIR="$tmp" \
  WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" \
  QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}" \
  timeout 25 \
  qs -p "$here/lockctx-timeout-test.qml" >"$log" 2>&1 || true

echo "--- harness log ---"; cat "$log"
if grep -q "TEST REARMED unlockInProgress=false" "$log" \
  && grep -q "TEST WATCH OK" "$log" \
  && grep -q "TEST SECOND COMPLETED" "$log" \
  && grep -q "TEST RESET-ON-MESSAGE OK" "$log" \
  && ! grep -q "TEST WATCH VIOLATION" "$log" \
  && ! grep -q "TEST UNEXPECTED UNLOCK" "$log" \
  && ! grep -q "TEST RESET-ON-MESSAGE FAIL" "$log" \
  && ! grep -q "while it is active" "$log"; then
  echo "PASS"; exit 0
else
  echo "FAIL: context did not re-arm cleanly and become usable again"; exit 1
fi
