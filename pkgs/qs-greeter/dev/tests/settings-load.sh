#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/defaults.json" <<'JSON'
{ "skin": "xp",
  "skins": { "xp": { "palettes": ["luna", "gruvbox"] } },
  "skinSettings": { "xp": { "palette": "luna" } },
  "backdrop": { "kind": "color", "color": "#3A6EA5", "image": null, "fit": "cover" },
  "sessions": { "picker": true, "default": null },
  "optionsExpanded": false,
  "rememberLastUser": true,
  "branding": { "title": "Log On to Windows", "subtitle": "Microsoft Windows XP  Professional" } }
JSON

cat >"$tmp/settings.json" <<'JSON'
{ "version": 1,
  "skinSettings": { "xp": { "palette": "gruvbox" } },
  "backdrop": { "kind": "image", "image": "bliss.jpg" } }
JSON

cat >"$tmp/corrupt.json" <<'JSON'
{ not valid json
JSON

overall=0

# `qs -p` never returns control on its own in this environment: Qt.quit()
# is emitted with no receiver wired up whenever it fires before Quickshell's
# own startup has finished ("Signal QQmlEngine::quit() emitted, but no
# receivers connected to handle it"), and the process then idles forever
# (reproduces on the already-shipped merge-test.qml too -- a pre-existing
# Quickshell headless-mode quirk, not something introduced here). `timeout`
# bounds each run once the result line has had time to print; `|| true`
# keeps the forced-kill exit code from tripping `set -e` after the output
# has already been captured.
run_qs() {
  local test_file="$1" user_file="$2"
  QSG_DEFAULTS="$tmp/defaults.json" \
  QSG_USER_FILE="$user_file" \
  QSG_BACKDROP_DIR=/tmp/qsg-test-backdrops \
    timeout 20 qs -p "$here/$test_file" 2>&1 || true
}

# check_case fails (nonzero, and bumps $overall) unless the QML printed an
# EXACT "SETTINGS-TEST PASS" summary line -- not a bare substring match on
# "SETTINGS-TEST", which matches the FAIL line just as happily. That
# substring bug is what let this runner exit 0 on a broken merge before. A
# syntax error or crash prints no SETTINGS-TEST line at all and is caught by
# the same not-found branch.
check_case() {
  local label="$1" out="$2" want_warning="$3" # want_warning: yes | no | dontcare
  echo "--- $label ---"
  echo "$out" | grep SETTINGS-TEST || echo "(no SETTINGS-TEST line -- crash or syntax error)"

  if ! echo "$out" | grep -q "SETTINGS-TEST PASS"; then
    echo "FAIL: $label did not report a clean PASS"
    overall=1
    return
  fi

  case "$want_warning" in
    yes)
      if ! echo "$out" | grep -q "qs-greeter W"; then
        echo "FAIL: $label expected a warning, none was logged"
        overall=1
      fi
      ;;
    no)
      if echo "$out" | grep -q "qs-greeter W"; then
        echo "FAIL: $label expected silence, but a warning was logged"
        overall=1
      fi
      ;;
  esac
}

out="$(run_qs settings-load-test.qml "$tmp/settings.json")"
check_case "primary merge (user tier overrides win)" "$out" dontcare

out="$(run_qs settings-defaults-test.qml "$tmp/no-such-file.json")"
check_case "missing user file (first boot, must be silent)" "$out" no

out="$(run_qs settings-defaults-test.qml "$tmp/corrupt.json")"
check_case "corrupt user file (must warn and fall back)" "$out" yes

exit "$overall"
