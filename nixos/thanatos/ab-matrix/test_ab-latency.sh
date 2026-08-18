#!/usr/bin/env bash
# Unit tests for the pure helpers in ab-latency.sh. These run without root and
# without touching a single tunable, so a broken harness is caught before a
# four-hour run rather than after it.
set -uo pipefail

TARGET="${AB_LATENCY_TARGET:-$(dirname "$0")/ab-latency.sh}"
# shellcheck source=/dev/null
AB_LATENCY_SOURCED=1 . "$TARGET"

fail=0
check() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1: got '$2' want '$3'"
    fail=1
  fi
}

check "cell count is the full factorial" "$(cell_count)" "48"
check "cells are unique" "$(block_cells | sort -u | wc -l)" "48"
check "cells emitted equals cells counted" "$(block_cells | wc -l)" "$(cell_count)"

check "dirty low"  "$(dirty_bytes_for low)"  "67108864 16777216"
check "dirty high" "$(dirty_bytes_for high)" "268435456 67108864"

# Every level of every factor must appear, or a typo silently drops an arm and
# the run measures a smaller matrix than it reports.
check "bfq present"   "$(block_cells | grep -c '^bfq:')"   "16"
check "kyber present" "$(block_cells | grep -c '^kyber:')" "16"
check "adios present" "$(block_cells | grep -c '^adios:')" "16"
check "cpuw on/off balanced" "$(block_cells | grep -c ':on$')" "24"

# Deterministic shuffle: a run must be reproducible from its seed.
a="$(block_cells | shuffle_seeded 7 | md5sum)"
b="$(block_cells | shuffle_seeded 7 | md5sum)"
c="$(block_cells | shuffle_seeded 8 | md5sum)"
check "shuffle deterministic" "$([ "$a" = "$b" ] && echo yes || echo no)" "yes"
check "shuffle seed-sensitive" "$([ "$a" != "$c" ] && echo yes || echo no)" "yes"
check "shuffle preserves every cell" "$(block_cells | shuffle_seeded 7 | sort -u | wc -l)" "48"

# Budget arithmetic. 48 cells x 285s = 13680s; two reps must not fit in 5h.
SETTLE=45 MEASURE=210
check "cell seconds"      "$(cell_seconds)"          "285"
check "one rep seconds"   "$(estimate_seconds 1)"    "13680"
check "two reps seconds"  "$(estimate_seconds 2)"    "27360"
check "only 1 rep fits 5h" "$(reps_that_fit 18000)"  "1"
check "2 reps fit 8h"      "$(reps_that_fit 28800)"  "2"
check "fmt_hms"            "$(fmt_hms 13680)"        "3h48m"

# PSI parsing against a fixture, so a kernel format change is caught here
# rather than as a column of zeroes in the results.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/io.pressure" <<'EOF'
some avg10=0.00 avg60=0.00 avg300=0.05 total=192418536
full avg10=0.00 avg60=0.00 avg300=0.04 total=153187155
EOF
check "psi some total" "$(psi_total "$tmp" io some)" "192418536"
check "psi full total" "$(psi_total "$tmp" io full)" "153187155"
check "psi missing file is empty" "$(psi_total "$tmp" nosuch some)" ""

# The daemon assertion is the one preflight check whose failure mode is a
# false NEGATIVE that aborts a four-hour run before it starts, and it broke on
# two separate subtleties: `nix store info` writes its human output to stderr,
# so filtering stderr away left nothing to match; and `grep -q` plus pipefail
# reports a successful match as a failed pipeline. Pin both here, where they
# cost two seconds instead of a wasted evening.
check "nix store info --json writes to stdout" \
  "$([ -n "$(NIX_REMOTE=daemon nix store info --json 2>/dev/null)" ] && echo yes || echo no)" \
  "yes"
check "daemon_ok true when the daemon answers" \
  "$(daemon_ok && echo yes || echo no)" "yes"

# hwmon must resolve by name; a missing sensor must report empty rather than 0,
# because "absent" and "cold" are not the same reading.
check "hwmon absent name is empty" "$(hwmon_temp definitely-not-a-sensor)" ""

exit "$fail"
