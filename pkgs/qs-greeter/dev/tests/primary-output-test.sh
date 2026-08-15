#!/usr/bin/env bash
# Headless verification of PrimaryOutput.js (final micro-fix, Item 1): an
# exact "PRIMARY-OUTPUT-TEST PASS n/n" line is the only way this counts as
# passing -- a "FAIL ..." line, or no result line at all (crash or syntax
# error), is a nonzero exit. Same convention every other suite in this
# directory uses; see settings-load.sh's own comment for the substring-
# match bug this guards against.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT

env QT_QPA_PLATFORM=offscreen timeout 20 qs -p "$here/primary-output-test.qml" >"$out" 2>&1 || true

cat "$out"
if grep -qE "PRIMARY-OUTPUT-TEST PASS [0-9]+/[0-9]+" "$out"; then
  exit 0
else
  echo "FAIL: primary-output-test.qml did not report a clean PASS"
  exit 1
fi
