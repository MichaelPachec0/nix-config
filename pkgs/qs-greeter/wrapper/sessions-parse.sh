#!/usr/bin/env bash
# Build the greeter's session list from wayland-session desktop files.
#
# Runs at greeter start rather than at Nix evaluation time so that reading the
# session directory does not force an import-from-derivation. The trust
# boundary is unchanged: that directory is root-owned store content, and the
# resulting argv is never influenced by the group-writable settings file.
#
# usage: sessions-parse.sh <sessionsDir> <uwsm|all> <extraJson> <shellsJson>
set -euo pipefail

dir="${1:?sessions dir required}"
filter="${2:?filter required}"
extra="${3:-[]}"
shells="${4:-[]}"

entries="[]"

if [ -d "$dir" ]; then
  while IFS= read -r -d '' file; do
    base="$(basename "$file" .desktop)"
    if [ "$filter" = "uwsm" ]; then
      case "$base" in
        *-uwsm) ;;
        *) continue ;;
      esac
    fi

    # Only the [Desktop Entry] group matters; action groups can also carry
    # Name=/Exec= and would otherwise clobber the real values.
    body="$(awk '/^\[Desktop Entry\]/{f=1;next} /^\[/{f=0} f' "$file")"
    name="$(printf '%s\n' "$body" | sed -n 's/^Name=//p' | head -n1)"
    exec_line="$(printf '%s\n' "$body" | sed -n 's/^Exec=//p' | head -n1)"
    [ -n "$name" ] || name="$base"
    [ -n "$exec_line" ] || continue

    entries="$(jq \
      --arg name "$name" \
      --arg exec "$exec_line" \
      --arg base "$base" \
      '. + [{
         name: $name,
         argv: ($exec | split(" ") | map(select(length > 0))),
         env: {
           XDG_SESSION_DESKTOP: $base,
           DESKTOP_SESSION: $base
         }
       }]' <<<"$entries")"
  done < <(find "$dir" -maxdepth 1 -name '*.desktop' -print0 | sort -z)
fi

jq -c -n \
  --argjson graphical "$entries" \
  --argjson extra "$extra" \
  --argjson shells "$shells" \
  '$graphical + $extra + $shells'
