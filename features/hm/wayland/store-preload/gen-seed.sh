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

# Capture ldd separately, as a plain assignment: `set -e` then fails the
# build if ldd itself fails (absent, wrong ELF class, exit 127/1), nothing
# swallows it. Old bug: one `|| true` covered ldd AND the grep/sort below, so
# a truncated ldd (some deps, then non-zero) shipped a truncated seed.
ldd_out=$(ldd "$real")

# grep -o (zero deps) or the final grep -vxF (no OTHER deps) can legitimately
# exit 1 with no error. ldd already succeeded above, so `|| [ $? -eq 1 ]`
# masks only "no deps found", never an ldd failure or any other exit code.
deps=$(printf '%s\n' "$ldd_out" | grep -o '/nix/store/[^ )]*' | sort -u | grep -vxF "$real") \
  || [ $? -eq 1 ]

{
  echo "$real"
  [ -z "$deps" ] || printf '%s\n' "$deps"
} > "$out"

if [ "$(head -1 "$out")" != "$real" ]; then
  echo "gen-seed: first line of $out is not the real binary ($real)" >&2
  exit 1
fi
