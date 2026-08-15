#!/usr/bin/env bash
# Headless verification of the XP widget kit (Task 9): instantiates every
# widget in every state offscreen and asserts on measurable properties --
# see widgets-gallery.qml for what "every state" covers and why this
# stands in for the brief's Step 5 nested-compositor eyeball pass (this
# process must never be run against the user's real session).
#
# Fails loudly on four independent conditions, not just a missing PASS:
#   1. no "GALLERY-TEST" line at all (crash or QML load/type error)
#   2. a "GALLERY-TEST FAIL n/m" line (an assertion did not hold)
#   3. a disallowed warning substring (Binding loop / Unable to assign /
#      ReferenceError / TypeError) anywhere in the run's output
#   4. any other Quickshell "scene"-category warning (its channel for
#      runtime QML problems in general) not already covered by #3 and not
#      on the benign allowlist below
#
# #3 and #4 exist because a misspelled theme.* reference (e.g.
# theme.buttonTextTypoBroken instead of theme.buttonText) does NOT fail the
# GALLERY-TEST assertions -- QML resolves the unknown property to
# `undefined`, logs "Unable to assign [undefined] to QColor" as a
# *warning*, and keeps running with whatever the property's default was.
# The harness printed a clean "GALLERY-TEST PASS 37/37" with that exact
# mutation in place until this check was added (see the fix-round-1 report
# appendix in task-9-report.md for the reproduction). This is precisely the
# failure mode the no-literal-colors architecture is supposed to make
# impossible to ship silently: the grep catches a hardcoded color, this
# catches a theme reference that resolves to nothing.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# qs -p does not reliably return control on Qt.quit() in this environment
# (see settings-load.sh's comment on the same quirk); timeout bounds the
# run once the result line has had time to print. Written straight to a
# file (see fonts-eval.sh's own comment on the same choice) rather than
# captured into a shell variable, so a very noisy run can't trip an
# "Argument list too long" while being piped through grep.
QT_QPA_PLATFORM=offscreen timeout 20 qs -p "$here/widgets-gallery.qml" >"$tmp" 2>&1 || true

grep GALLERY-TEST "$tmp" || echo "(no GALLERY-TEST line -- crash or QML load error)"

overall=0

if ! grep -q "GALLERY-TEST PASS" "$tmp"; then
  echo "FAIL: widgets-gallery.qml did not report a clean PASS"
  overall=1
fi

# Known-benign lines that would otherwise trip the checks below. Every
# entry here was seen in an actual clean run and hand-verified not to
# indicate a real problem -- adding to this list is a "prove it's benign"
# action, not a silence-the-noise reflex, per the coordinator's ruling.
benign_allowlist=(
  "WAYLAND_DISPLAY is present but QT_QPA_PLATFORM is"
  "If you are actually running wayland"
  "--- WARNING ---"
  "Signal QQmlEngine::quit() emitted, but no receivers connected to handle it."
  "Module path contains invalid characters for a module name"
)

is_allowlisted() {
  local line="$1" pat
  for pat in "${benign_allowlist[@]}"; do
    [[ "$line" == *"$pat"* ]] && return 0
  done
  return 1
}

# Explicit, named failure classes -- the minimum the coordinator asked for
# (Unable to assign, ReferenceError), plus Binding loop (already checked
# before this fix round, now folded into the same loop) and TypeError
# (Qt's own message for e.g. calling a method on undefined, the same class
# of bug as the ReferenceError this round's fix was proving out).
danger_patterns=(
  "Binding loop"
  "Unable to assign"
  "ReferenceError"
  "TypeError"
)

while IFS= read -r line; do
  [ -z "$line" ] && continue
  is_allowlisted "$line" && continue

  matched=0
  for pat in "${danger_patterns[@]}"; do
    if [[ "$line" == *"$pat"* ]]; then
      echo "FAIL: widgets-gallery.qml run logged a disallowed warning: $line"
      overall=1
      matched=1
    fi
  done
  # General net: any other Quickshell "scene"-category warning (its
  # logging channel for runtime QML problems generally -- this is where
  # every pattern above already shows up, so this exists to catch whatever
  # they don't think to name, e.g. a warning message Qt phrases
  # differently in a future version).
  if [ "$matched" -eq 0 ] && [[ "$line" == *"WARN"*"scene"* ]]; then
    echo "FAIL: widgets-gallery.qml run logged a QML scene warning: $line"
    overall=1
  fi
done <"$tmp"

exit "$overall"
