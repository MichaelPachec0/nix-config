#!/usr/bin/env bash
# Headless verification of Task 11 (the XP "Shut Down Windows" modal,
# ShutDownDialog.qml, and its wiring into Skin.qml): drives the real
# ShutDownDialog.qml standalone AND through the real Skin.qml (reached via
# xp-kit/, same mirror technique skin-smoke-test.qml and
# logon-dialog-test.qml already use), never through shell.qml -- there is
# no Process/Quickshell.Io anywhere in shutdown-dialog-test.qml's import
# graph, so this run cannot invoke a real systemctl call even by accident.
# QT_QPA_PLATFORM=offscreen, no window, no focus stolen, must never be run
# against the user's real session.
#
# Fails loudly the same way logon-dialog-test.sh does: an exact
# "SHUTDOWN-TEST PASS n/n" line is the only way this counts as passing. A
# "SHUTDOWN-TEST FAIL ..." line, or no result line at all (crash or syntax
# error), is a nonzero exit. On top of that, the output is scanned for the
# same disallowed-warning classes widgets-gallery.sh/logon-dialog-test.sh
# check for (Binding loop / Unable to assign / ReferenceError / TypeError /
# any other "scene"-category warning) -- a misspelled theme.* reference
# resolves to `undefined` and keeps running with a warning, not a failed
# assertion, so a clean PASS line does not by itself prove there is no such
# typo in ShutDownDialog.qml or Skin.qml's new wiring.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

sessions_json='[
  {"name":"Hyprland (uwsm-managed)","argv":["uwsm","start","-S","-F","/nix/store/fake-hypr/bin/Hyprland"],"env":{"XDG_SESSION_DESKTOP":"hyprland-uwsm"}},
  {"name":"zsh (console)","argv":["/nix/store/fake-zsh/bin/zsh","-l"],"env":{}}
]'
printf '%s' "$sessions_json" >"$tmp/sessions.json"

cat >"$tmp/defaults.json" <<'JSON'
{ "skin": "xp",
  "skins": { "xp": { "palettes": ["luna", "gruvbox"] } },
  "skinSettings": { "xp": { "palette": "luna" } },
  "backdrop": { "kind": "color", "color": "#3A6EA5", "image": null, "fit": "cover" },
  "sessions": { "picker": false, "default": null },
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
# behavior -- Settings.qml/GreeterState.qml both already treat a missing
# file as "not an error"; see logon-dialog-test.sh's own allowlist entry
# for the FileView-level warning this produces regardless).
env QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen \
  QSG_DEFAULTS="$tmp/defaults.json" \
  QSG_USER_FILE="$tmp/no-such-user-file.json" \
  QSG_SESSIONS="$tmp/sessions.json" \
  QSG_STATE_FILE="$tmp/no-such-state-file.json" \
  timeout 20 qs -p "$here/shutdown-dialog-test.qml" >"$out" 2>&1 || true

grep SHUTDOWN-TEST "$out" || echo "(no SHUTDOWN-TEST line -- crash or syntax error)"
if ! grep -qE "SHUTDOWN-TEST PASS [0-9]+/[0-9]+" "$out"; then
  echo "FAIL: shutdown-dialog-test.qml did not report a clean PASS"
  overall=1
fi

# --- disallowed-warning scan, same allowlist/patterns as
# logon-dialog-test.sh (see its own header for the story this guards
# against). ---
benign_allowlist=(
  "WAYLAND_DISPLAY is present but QT_QPA_PLATFORM is"
  "If you are actually running wayland"
  "--- WARNING ---"
  "Signal QQmlEngine::quit() emitted, but no receivers connected to handle it."
  "Module path contains invalid characters for a module name"
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
done <"$out"

exit "$overall"
