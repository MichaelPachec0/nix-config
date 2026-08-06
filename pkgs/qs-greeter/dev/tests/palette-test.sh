#!/usr/bin/env bash
# Headless verification of Task 12 (the Gruvbox palette and Skin.qml's
# palette-selection/fallback wiring): runs palette-test.qml, which is the
# substantive check this task exists for -- see that file's own header for
# what Parts A-D each prove (property audit, geometry invariance, colors
# actually differ, unregistered-name fallback).
#
# QSG_DEFAULTS below sets skinSettings.xp.palette to an UNREGISTERED name on
# purpose (Part D's fixture): SettingsMerge.js only validates a palette name
# arriving through the user tier (see its own "skinSettings" case), so the
# Nix-owned defaults tier is the one place this codebase can hand Skin.qml
# an unknown name without going through that validation at all -- exactly
# what Part D needs to drive Skin.qml's own fallback rather than
# SettingsMerge.js's.
#
# Fails loudly the same way every other runner in this directory does: an
# exact "PALETTE-TEST PASS n/n" line is the only way this counts as passing.
# A "PALETTE-TEST FAIL ..." line, or no result line at all (crash or syntax
# error), is a nonzero exit. On top of that, the output is scanned for the
# same disallowed-warning classes widgets-gallery.sh/logon-dialog-test.sh
# check for (Binding loop / Unable to assign / ReferenceError / TypeError /
# any other "scene"-category warning) -- a misspelled theme.* reference in
# Gruvbox.qml resolves to `undefined` and keeps running with a warning, not
# a failed assertion, so a clean PASS line does not by itself prove there is
# no such typo.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/defaults.json" <<'JSON'
{ "skin": "xp",
  "skins": { "xp": { "palettes": ["luna", "gruvbox"] } },
  "skinSettings": { "xp": { "palette": "not-a-registered-palette" } },
  "backdrop": { "kind": "color", "color": "#3A6EA5", "image": null, "fit": "cover" },
  "sessions": { "picker": true, "default": null },
  "optionsExpanded": false,
  "rememberLastUser": true,
  "branding": { "title": "Log On to Windows", "subtitle": "Microsoft Windows XP  Professional" } }
JSON

overall=0
out="$tmp/out.log"

# qs -p does not reliably return control on Qt.quit() in this environment
# (see settings-load.sh's own comment on the same quirk); timeout bounds
# the run once the result line has had time to print. QSG_USER_FILE/
# QSG_STATE_FILE point at paths that do not exist on purpose (first-boot
# behavior, same as every other runner in this directory).
env QT_QPA_PLATFORM=offscreen \
  QSG_DEFAULTS="$tmp/defaults.json" \
  QSG_USER_FILE="$tmp/no-such-user-file.json" \
  QSG_SESSIONS="$tmp/no-such-sessions.json" \
  QSG_STATE_FILE="$tmp/no-such-state-file.json" \
  timeout 20 qs -p "$here/palette-test.qml" >"$out" 2>&1 || true

grep PALETTE-TEST "$out" || echo "(no PALETTE-TEST line -- crash or syntax error)"
if ! grep -qE "PALETTE-TEST PASS [0-9]+/[0-9]+" "$out"; then
  echo "FAIL: palette-test.qml did not report a clean PASS"
  overall=1
fi

# Part D's own evidence: the exact Log.warn text Skin.qml's fallback emits
# (see Skin.qml's `theme` property) must actually have fired, not just that
# the fallback's VALUE assertions happened to pass some other way.
if ! grep -q "skins/xp: unknown palette 'not-a-registered-palette', falling back to luna" "$out"; then
  echo "FAIL: Skin.qml's fallback warning did not fire for the unregistered palette name"
  overall=1
fi

# --- disallowed-warning scan, same allowlist/patterns as every other
# runner in this directory (see widgets-gallery.sh's own header for the
# theme.buttonTextTypoBroken story this guards against). ---
benign_allowlist=(
  "WAYLAND_DISPLAY is present but QT_QPA_PLATFORM is"
  "If you are actually running wayland"
  "--- WARNING ---"
  "Signal QQmlEngine::quit() emitted, but no receivers connected to handle it."
  "Module path contains invalid characters for a module name"
  "failed: File does not exist."
  # Part D's own fixture is an unregistered palette name reaching
  # Skin.qml's fallback -- Log.warn is deliberately fired here (checked
  # above by exact text), so its own "qs-greeter W" line must not also
  # trip the generic scene-warning net below (it does not match any
  # danger_pattern or the "WARN...scene" net as-is, since Log.warn logs on
  # the plain "qml" channel, not "scene" -- allowlisted anyway so a future
  # change to Log.qml's channel does not silently start failing this run).
  "qs-greeter W skins/xp: unknown palette"
)
is_allowlisted() {
  local line="$1" pat
  for pat in "${benign_allowlist[@]}"; do
    [[ "$line" == *"$pat"* ]] && return 0
  done
  return 1
}
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
      echo "FAIL: a run logged a disallowed warning: $line"
      overall=1
      matched=1
    fi
  done
  if [ "$matched" -eq 0 ] && [[ "$line" == *"WARN"*"scene"* ]]; then
    echo "FAIL: a run logged a QML scene warning: $line"
    overall=1
  fi
done <"$out"

exit "$overall"
