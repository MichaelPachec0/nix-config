#!/usr/bin/env bash
# The architectural rule Task 9 exists to enforce: every widget under
# skins/xp/widgets/ reads colors only through the theme object it is
# handed, never a literal color. This is what makes a palette swap
# (Task 12's Gruvbox, swapped in for Luna) a single-object substitution
# instead of a hunt through widget code.
#
# Checks four literal color forms, not just 6-digit hex:
#   1. #rrggbb   (the original check)
#   2. #rgb      (the 3-digit shorthand QColor also accepts)
#   3. Qt.rgba(...) / Qt.hsla(...) / Qt.rgb(...) / Qt.hsl(...) calls
#   4. a set of common CSS/SVG color keywords, quoted the way this
#      codebase writes them (e.g. "black", "orange") -- not exhaustive
#      (QColor recognizes ~147 SVG names), but covers the ones a widget
#      is actually likely to reach for instead of theme.*
#
# "transparent" is deliberately NOT in that keyword list: it is not a
# color a palette would ever want to override (there is no "Gruvbox
# transparent"), so five legitimate uses of it across these widgets
# (gradient-vs-flat togglable fills, an inset rectangle's own fill) are
# not violations of the rule this check enforces and must keep passing.
#
# Fails loudly: prints whatever it found (so a violation is diagnosable
# without re-running the checks by hand) and exits nonzero if anything
# matched. A clean run prints a PASS line and exits 0 -- `grep -q` itself
# exits 1 on "no match", which is success here, so the exit code is
# inverted explicitly rather than relied on directly.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
widgets_dir="$root/greeter/skins/xp/widgets"

overall=0

check() {
  local label="$1" pattern="$2"
  local hits
  hits="$(grep -rnE "$pattern" "$widgets_dir" || true)"
  if [ -n "$hits" ]; then
    echo "FAIL: $label found under $widgets_dir"
    echo "$hits"
    overall=1
  fi
}

check "6-digit hex literals (#rrggbb)" '#[0-9A-Fa-f]{6}\b'
check "3-digit hex literals (#rgb)" '#[0-9A-Fa-f]{3}\b'
check "Qt.rgba/hsla/rgb/hsl(...) literals" 'Qt\.(rgba|hsla|rgb|hsl)\('

# Common CSS/SVG color keywords as QML would actually write them: a
# quoted string, the same way "transparent" appears in these files today.
# Deliberately excludes "transparent" (see the header comment above).
named_colors='red|blue|green|yellow|orange|purple|pink|black|white|gray|grey|cyan|magenta|brown|navy|teal|silver|gold|maroon|olive|lime|indigo|violet|crimson|salmon|khaki|coral|turquoise|beige|ivory|lavender'
check "common named-color string literals" "\"($named_colors)\""

if [ "$overall" -eq 0 ]; then
  echo "no-literal-colors PASS: no literal colors under $widgets_dir"
fi

exit "$overall"
