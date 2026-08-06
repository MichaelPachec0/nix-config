#!/usr/bin/env bash
# The architectural rule Task 9 exists to enforce: every widget under
# skins/xp/widgets/ reads colors only through the theme object it is
# handed, never a literal hex color. This is what makes a palette swap
# (Task 12's Gruvbox, swapped in for Luna) a single-object substitution
# instead of a hunt through widget code.
#
# Fails loudly: prints whatever it found (so a violation is diagnosable
# without re-running the grep by hand) and exits nonzero if anything
# matched. A clean run prints nothing and exits 0 -- `grep -q` itself exits
# 1 on "no match", which is success here, so the exit code is inverted
# explicitly rather than relied on directly.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
widgets_dir="$root/greeter/skins/xp/widgets"

hits="$(grep -rn '#[0-9A-Fa-f]\{6\}' "$widgets_dir" || true)"

if [ -n "$hits" ]; then
  echo "FAIL: literal colors found under $widgets_dir"
  echo "$hits"
  exit 1
fi

echo "no-literal-colors PASS: no literal colors under $widgets_dir"
exit 0
