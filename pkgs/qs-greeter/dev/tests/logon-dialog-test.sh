#!/usr/bin/env bash
# Headless verification of Task 10 (the XP logon dialog, CapsLock, State,
# SkinFatal, and Skin.qml assembling them): drives the real Session state
# machine through MockBackend's scenarios against the real LogonDialog.qml,
# same as session-test.sh drives Session alone. This stands in for the
# brief's Step 5 nested-compositor eyeball pass -- this process must never
# be run against the user's real session (QT_QPA_PLATFORM=offscreen, no
# window, no focus stolen).
#
# Runs five sub-checks, each into its OWN output file (not one shared,
# appended-to log -- an earlier run's "<TAG> PASS" line staying on disk
# would let grep -q find it again for a LATER run of the same tag and mask
# a real failure there), and fails loudly on any of them: an exact
# "<TAG> PASS n/n" line is the only way a sub-check counts as passing. A
# "<TAG> FAIL ..." line, or no result line at all (crash or syntax error),
# is a nonzero exit -- see settings-load.sh's own comment on the
# substring-match bug this guards against.
#
# On top of that, the COMBINED output of every run is scanned for the same
# disallowed-warning classes widgets-gallery.sh checks for the widget kit
# (Binding loop / Unable to assign / ReferenceError / TypeError / any other
# "scene"-category warning): a misspelled theme.* or Settings.* reference
# resolves to `undefined` and keeps running with a warning, not a failed
# assertion, so the assertions passing cleanly does not by itself prove
# there is no such typo anywhere in the five new/changed files this run
# actually constructs (CapsLock.qml, State.qml, LogonDialog.qml,
# SkinFatal.qml, Skin.qml).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

sessions_json='[
  {"name":"Hyprland (uwsm-managed)","argv":["uwsm","start","-S","-F","/nix/store/fake-hypr/bin/Hyprland"],"env":{"XDG_SESSION_DESKTOP":"hyprland-uwsm"}},
  {"name":"Sway (uwsm-managed)","argv":["uwsm","start","-S","-F","/nix/store/fake-sway/bin/sway"],"env":{"XDG_SESSION_DESKTOP":"sway-uwsm"}},
  {"name":"zsh (console)","argv":["/nix/store/fake-zsh/bin/zsh","-l"],"env":{}}
]'
printf '%s' "$sessions_json" >"$tmp/sessions.json"

defaults_common='"skin": "xp",
  "skins": { "xp": { "palettes": ["luna", "gruvbox"] } },
  "skinSettings": { "xp": { "palette": "luna" } },
  "backdrop": { "kind": "color", "color": "#3A6EA5", "image": null, "fit": "cover" },
  "optionsExpanded": false,
  "rememberLastUser": true,
  "branding": { "title": "Log On to Windows", "subtitle": "Microsoft Windows XP  Professional" }'

cat >"$tmp/defaults-picker-on.json" <<JSON
{ $defaults_common,
  "sessions": { "picker": true, "default": null } }
JSON

# Task 12: the same picker-on fixture, but with Settings' own palette set to
# gruvbox -- used only for the skin-smoke-test.qml run below, the one run in
# this file that actually goes through Skin.qml's real Settings.palette
# resolution (logon-dialog-test.qml itself is handed a theme instance
# directly -- see its own QSG_TEST_PALETTE comment -- so it does not need a
# second defaults file at all).
defaults_common_gruvbox='"skin": "xp",
  "skins": { "xp": { "palettes": ["luna", "gruvbox"] } },
  "skinSettings": { "xp": { "palette": "gruvbox" } },
  "backdrop": { "kind": "color", "color": "#3A6EA5", "image": null, "fit": "cover" },
  "optionsExpanded": false,
  "rememberLastUser": true,
  "branding": { "title": "Log On to Windows", "subtitle": "Microsoft Windows XP  Professional" }'
cat >"$tmp/defaults-picker-on-gruvbox.json" <<JSON
{ $defaults_common_gruvbox,
  "sessions": { "picker": true, "default": null } }
JSON

cat >"$tmp/defaults-default-sway.json" <<JSON
{ $defaults_common,
  "sessions": { "picker": true, "default": "Sway (uwsm-managed)" } }
JSON

cat >"$tmp/defaults-nodefault.json" <<JSON
{ $defaults_common,
  "sessions": { "picker": true, "default": null } }
JSON

cat >"$tmp/defaults-picker-off.json" <<JSON
{ $defaults_common,
  "sessions": { "picker": false, "default": null } }
JSON

printf '{"lastUser":"prior","lastSession":"zsh (console)"}' >"$tmp/state-zsh.json"

# qs -p does not reliably return control on Qt.quit() in this environment
# (see settings-load.sh's comment on the same quirk); timeout bounds each
# run once the result line has had time to print. QML_XHR_ALLOW_FILE_READ=1
# is MockBackend.loadScenario()'s own requirement (synchronous XHR read of
# scenarios/*.json -- see session-test.sh). Each run gets its own output
# file, passed explicitly rather than inferred, so there is no shared
# mutable log for a later run's grep to accidentally match against an
# earlier run's line.
run_qs() {
  local outfile="$1" file="$2"
  shift 2
  env QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen "$@" \
    timeout 20 qs -p "$here/$file" >"$outfile" 2>&1 || true
}

overall=0
all_out="$tmp/all.log"
: >"$all_out"

check_case() {
  local label="$1" tag="$2" outfile="$3"
  echo "--- $label ---"
  grep "$tag" "$outfile" || echo "(no $tag line -- crash or syntax error)"
  if ! grep -qE "$tag PASS [0-9]+/[0-9]+" "$outfile"; then
    echo "FAIL: $label did not report a clean PASS"
    overall=1
  fi
  cat "$outfile" >>"$all_out"
}

# Task 12: the deep behavioral suite (52 assertions, none of them about
# color) run once per registered palette -- QSG_TEST_PALETTE picks which
# Theme instance logon-dialog-test.qml hands to the real LogonDialog.qml
# (see that file's own comment). This is what proves the suite's ~50
# assertions still hold when the palette underneath the exact same widget
# tree is not Luna: label text, echo mode, row-height STABILITY (never
# whether two DIFFERENT palettes produce the same row height -- that cross-
# palette geometry comparison is palette-test.sh's job, not this file's),
# session-combo ordering, Caps Lock balloon, blocked-countdown status line,
# and every signal-wiring path Task 10 already covers.
for palette in luna gruvbox; do
  out1="$tmp/out1-$palette.log"
  run_qs "$out1" logon-dialog-test.qml \
    QSG_DEFAULTS="$tmp/defaults-picker-on.json" \
    QSG_USER_FILE="$tmp/no-such-user-file.json" \
    QSG_SESSIONS="$tmp/sessions.json" \
    QSG_STATE_FILE="$tmp/state-main-$palette.json" \
    QSG_TEST_PALETTE="$palette"
  check_case "logon-dialog-test.qml (deep behavioral suite, palette=$palette)" "LOGON-TEST" "$out1"
done

out2="$tmp/out2.log"
run_qs "$out2" logon-dialog-precedence-test.qml \
  QSG_DEFAULTS="$tmp/defaults-default-sway.json" \
  QSG_USER_FILE="$tmp/no-such-user-file.json" \
  QSG_SESSIONS="$tmp/sessions.json" \
  QSG_STATE_FILE="$tmp/state-zsh.json" \
  QSG_TEST_EXPECT_PRESELECT="Sway (uwsm-managed)"
check_case "precedence: Settings.default beats State.lastSession" "LOGON-PRECEDENCE-TEST" "$out2"

out3="$tmp/out3.log"
run_qs "$out3" logon-dialog-precedence-test.qml \
  QSG_DEFAULTS="$tmp/defaults-nodefault.json" \
  QSG_USER_FILE="$tmp/no-such-user-file.json" \
  QSG_SESSIONS="$tmp/sessions.json" \
  QSG_STATE_FILE="$tmp/state-zsh.json" \
  QSG_TEST_EXPECT_PRESELECT="zsh (console)"
check_case "precedence: State.lastSession beats first-entry" "LOGON-PRECEDENCE-TEST" "$out3"

out4="$tmp/out4.log"
run_qs "$out4" logon-dialog-precedence-test.qml \
  QSG_DEFAULTS="$tmp/defaults-picker-off.json" \
  QSG_USER_FILE="$tmp/no-such-user-file.json" \
  QSG_SESSIONS="$tmp/sessions.json" \
  QSG_STATE_FILE="$tmp/state-main-off.json" \
  QSG_TEST_PICKER_OFF=1
check_case "precedence: Options is a no-op when the picker is disabled" "LOGON-PRECEDENCE-TEST" "$out4"

# Task 12: construction-only smoke check, once per palette. This run goes
# through the REAL Skin.qml (unlike logon-dialog-test.qml above), so it is
# what actually exercises Settings.palette -> Skin.qml's palette-resolution
# `theme` property end to end for gruvbox, not just for luna.
for palette in luna gruvbox; do
  defaults="$tmp/defaults-picker-on.json"
  [ "$palette" = "gruvbox" ] && defaults="$tmp/defaults-picker-on-gruvbox.json"
  out5="$tmp/out5-$palette.log"
  run_qs "$out5" skin-smoke-test.qml \
    QSG_DEFAULTS="$defaults" \
    QSG_USER_FILE="$tmp/no-such-user-file.json" \
    QSG_SESSIONS="$tmp/sessions.json" \
    QSG_STATE_FILE="$tmp/state-smoke-$palette.json"
  check_case "skin-smoke-test.qml (Skin.qml/SkinFatal.qml construction, palette=$palette)" "SKIN-SMOKE-TEST" "$out5"
done

# --- disallowed-warning scan over the FULL combined output, same
# allowlist/patterns as widgets-gallery.sh (see its header for the
# theme.buttonTextTypoBroken story this guards against -- a bad reference
# resolves to `undefined` and logs a *warning*, not an assertion failure). ---
benign_allowlist=(
  "WAYLAND_DISPLAY is present but QT_QPA_PLATFORM is"
  "If you are actually running wayland"
  "--- WARNING ---"
  "Signal QQmlEngine::quit() emitted, but no receivers connected to handle it."
  "Module path contains invalid characters for a module name"
  # This runner deliberately points QSG_USER_FILE/QSG_STATE_FILE at paths
  # that do not exist, to exercise first-boot behavior (no prior user
  # settings, no prior recorded state) -- Settings.qml's own onLoadFailed
  # and GreeterState.qml's absent one both already treat a missing file as
  # "not an error" (see their own comments; settings-load.sh's "missing
  # user file (first boot, must be silent)" case tests exactly this at the
  # Log level). FileView's own lower-level diagnostic still logs a "scene"
  # warning regardless of what the QML around it does with the failure, so
  # it is allowlisted here rather than treated as this run's own bug.
  "failed: File does not exist."
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
done <"$all_out"

exit "$overall"
