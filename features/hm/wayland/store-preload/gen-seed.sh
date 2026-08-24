#!/usr/bin/env bash
# Build a store-preload seed file for one already-resolved real binary.
#
# main.py's seed_stamp() reads line 1 of the seed and treats it as the app's
# generation stamp: `files[0]`. Sorting the real binary in together with its
# ldd output reorders it into hash order, so the stamp silently becomes
# whatever dependency happens to sort first (measured: fontconfig, for both
# rofi and quickshell). Keep $real out of the sort, and assert the invariant
# so a future edit cannot reintroduce that bug without failing the build.
set -euo pipefail

real="${1:?usage: gen-seed.sh /path/to/real/binary /path/to/output}"
out="${2:?usage: gen-seed.sh /path/to/real/binary /path/to/output}"

# grep -vxF can legitimately match nothing (a real binary with no other
# /nix/store dependency string in `ldd`'s output) and exits 1 in that case;
# under `set -o pipefail` that would abort the script over a non-error, so
# it is captured with `|| true` rather than left in the pipeline directly.
deps=$(ldd "$real" | grep -o '/nix/store/[^ )]*' | sort -u | grep -vxF "$real" || true)

{
  echo "$real"
  [ -z "$deps" ] || printf '%s\n' "$deps"
} > "$out"

if [ "$(head -1 "$out")" != "$real" ]; then
  echo "gen-seed: first line of $out is not the real binary ($real)" >&2
  exit 1
fi
