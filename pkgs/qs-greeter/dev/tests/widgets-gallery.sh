#!/usr/bin/env bash
# Headless verification of the XP widget kit (Task 9): instantiates every
# widget in every state offscreen and asserts on measurable properties --
# see widgets-gallery.qml for what "every state" covers and why this
# stands in for the brief's Step 5 nested-compositor eyeball pass (this
# process must never be run against the user's real session).
#
# Fails loudly on three independent conditions, not just a missing PASS:
#   1. no "GALLERY-TEST" line at all (crash or QML load/type error)
#   2. a "GALLERY-TEST FAIL n/m" line (an assertion did not hold)
#   3. any "Binding loop" warning in the run's output -- Qt prints these as
#      warnings, not errors, so a widget with a binding loop would still
#      print a clean PASS line unless this is checked separately (the
#      brief calls this out explicitly: "Binding loops... are easy to
#      ship").
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

# qs -p does not reliably return control on Qt.quit() in this environment
# (see settings-load.sh's comment on the same quirk); timeout bounds the
# run once the result line has had time to print.
out="$(QT_QPA_PLATFORM=offscreen timeout 20 qs -p "$here/widgets-gallery.qml" 2>&1 || true)"

echo "$out" | grep GALLERY-TEST || echo "(no GALLERY-TEST line -- crash or QML load error)"

overall=0

if ! echo "$out" | grep -q "GALLERY-TEST PASS"; then
  echo "FAIL: widgets-gallery.qml did not report a clean PASS"
  overall=1
fi

if echo "$out" | grep -qi "Binding loop"; then
  echo "FAIL: widgets-gallery.qml run logged a Binding loop warning"
  echo "$out" | grep -i "Binding loop"
  overall=1
fi

exit "$overall"
