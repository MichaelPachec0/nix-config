#!/usr/bin/env bash
# Runs skins-test.qml with QSG_SKIN_ROOT pointed at dev/fixtures/skins, the
# only place the "broken" fixture is reachable from (see Skins.qml's
# _envRootTrusted gate -- production never sets this var, and even if it
# did, the override stays inert unless the target also carries the
# dev/fixtures/skins/.dev-only marker, which the real skins/ tree never
# ships). Fails loudly: exit 0 only if the QML reports an exact
# "SKINS-TEST PASS n/n" line. A "SKINS-TEST FAIL ..." line, or no result
# line at all (crash or syntax error), is a nonzero exit -- see
# settings-load.sh's check_case for the substring-match bug this guards
# against (it matched PASS and FAIL alike and exited 0 on a broken suite).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"

# qs -p does not reliably return control on Qt.quit() in this environment
# (see settings-load.sh); timeout bounds the run once the result line has
# had time to print.
out="$(QSG_SKIN_ROOT="$root/dev/fixtures/skins" timeout 20 qs -p "$here/skins-test.qml" 2>&1 || true)"

echo "$out" | grep SKINS-TEST || echo "(no SKINS-TEST line -- crash or syntax error)"

if echo "$out" | grep -q "SKINS-TEST PASS"; then
  exit 0
fi
echo "FAIL: skins-test.qml did not report a clean PASS"
exit 1
