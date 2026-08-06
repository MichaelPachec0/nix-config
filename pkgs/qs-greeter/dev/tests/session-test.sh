#!/usr/bin/env bash
# Runs session-test.qml and fails loudly: exit 0 only on an exact
# "SESSION-TEST PASS" line. A "SESSION-TEST FAIL ..." line, or no
# SESSION-TEST line at all (crash or syntax error), is a nonzero exit --
# see settings-load.sh's check_case for the substring-match bug this
# guards against (it matched PASS and FAIL alike and exited 0 on a broken
# suite).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

# MockBackend.qml's loadScenario() reads dev/scenarios/*.json via a
# synchronous XMLHttpRequest; Quickshell disables local-file XHR reads
# unless this is set, and silently returns an empty response otherwise
# (JSON.parse then throws and every scenario load is a no-op).
#
# `qs -p` does not reliably return control on Qt.quit() in this
# environment (see settings-load.sh); `timeout` bounds the run once the
# result line has had time to print.
out="$(QML_XHR_ALLOW_FILE_READ=1 timeout 20 qs -p "$here/session-test.qml" 2>&1)" || true

echo "$out" | grep SESSION-TEST || echo "(no SESSION-TEST line -- crash or syntax error)"

if echo "$out" | grep -q "SESSION-TEST PASS"; then
  exit 0
else
  echo "FAIL: session-test.qml did not report a clean PASS"
  exit 1
fi
