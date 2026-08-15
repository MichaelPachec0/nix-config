#!/usr/bin/env bash
# Test the session-list generator against fixture desktop files.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
parse="$here/../../wrapper/sessions-parse.sh"
fixtures="$here/fixtures/wayland-sessions"
pass=0
total=0

check() {
  local name="$1" got="$2" want="$3"
  total=$((total + 1))
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    echo "SESSIONS-TEST CASE FAIL: $name"
    echo "  got:  $got"
    echo "  want: $want"
  fi
}

shells='[{"name":"zsh (console)","argv":["/nix/store/fake-zsh/bin/zsh","-l"],"env":{}}]'

out="$("$parse" "$fixtures" uwsm '[]' "$shells")"
check "uwsmCount" "$(echo "$out" | jq 'length')" "3"
check "uwsmFirstIsGraphical" "$(echo "$out" | jq -r '.[0].name')" "Hyprland (uwsm-managed)"
check "uwsmExcludesNative" "$(echo "$out" | jq '[.[] | select(.name == "Hyprland")] | length')" "0"
check "uwsmArgvSplit" "$(echo "$out" | jq -c '.[0].argv')" \
  '["uwsm","start","-S","-F","/nix/store/fake-hyprland/bin/Hyprland"]'
check "shellIsLast" "$(echo "$out" | jq -r '.[-1].name')" "zsh (console)"
check "desktopEnvSet" "$(echo "$out" | jq -r '.[0].env.XDG_SESSION_DESKTOP')" "hyprland-uwsm"

out="$("$parse" "$fixtures" all '[]' "$shells")"
check "allCount" "$(echo "$out" | jq 'length')" "4"
check "allIncludesNative" "$(echo "$out" | jq '[.[] | select(.name == "Hyprland")] | length')" "1"

extra='[{"name":"Custom","argv":["/bin/true"],"env":{"FOO":"bar"}}]'
out="$("$parse" "$fixtures" uwsm "$extra" "$shells")"
check "extraBeforeShells" "$(echo "$out" | jq -r '.[-2].name')" "Custom"
check "extraEnvKept" "$(echo "$out" | jq -r '.[-2].env.FOO')" "bar"

out="$("$parse" "$here/nonexistent" uwsm '[]' '[]')"
check "emptyDirIsEmptyArray" "$(echo "$out" | jq -c '.')" "[]"

if [ "$pass" = "$total" ]; then
  echo "SESSIONS-TEST PASS $pass/$total"
else
  echo "SESSIONS-TEST FAIL $pass/$total"
  exit 1
fi
