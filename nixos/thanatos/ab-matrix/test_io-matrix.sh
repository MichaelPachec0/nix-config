#!/usr/bin/env bash
# Unit tests for io-matrix.sh's pure helpers, plus an end-to-end check that a
# generated fio job really runs and that its real JSON really parses. These run
# without root and touch no tunable, so a broken harness is caught before a
# multi-hour run rather than after it.
set -uo pipefail

TARGET="${IO_MATRIX_TARGET:-$(dirname "$0")/io-matrix.sh}"
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Override before sourcing: the real WORKDIR is 40G on /home and the mountpoint
# guard would reject a scratch path anyway.
export OUTDIR="$TMP/out" WORKDIR="$TMP/work" WORKSET_GB=1 SETTLE=1 MEASURE=2
mkdir -p "$OUTDIR" "$WORKDIR"

# shellcheck source=/dev/null
IO_MATRIX_SOURCED=1 . "$TARGET"

fail=0
check() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1: got '$2' want '$3'"
    fail=1
  fi
}

check "cell count is the full factorial" "$(cell_count)" "24"
check "cells are unique" "$(block_cells | sort -u | wc -l)" "24"
check "cells emitted equals cells counted" "$(block_cells | wc -l)" "$(cell_count)"

# Every level of every factor must appear, or a typo silently drops an arm and
# the run measures a smaller matrix than it reports.
check "adios present" "$(block_cells | grep -c '^adios:')" "12"
check "kyber present" "$(block_cells | grep -c '^kyber:')" "12"
check "seqread present" "$(block_cells | grep -c ':seqread:')" "8"
check "randrw present"  "$(block_cells | grep -c ':randrw:')"  "8"
check "fsync present"   "$(block_cells | grep -c ':fsync:')"   "8"
check "iolat balanced"  "$(block_cells | grep -c ':on$')"      "12"

a="$(block_cells | shuffle_seeded 7 | md5sum)"
b="$(block_cells | shuffle_seeded 7 | md5sum)"
c="$(block_cells | shuffle_seeded 8 | md5sum)"
check "shuffle deterministic"  "$([ "$a" = "$b" ] && echo yes || echo no)" "yes"
check "shuffle seed-sensitive" "$([ "$a" != "$c" ] && echo yes || echo no)" "yes"
check "shuffle preserves every cell" "$(block_cells | shuffle_seeded 7 | sort -u | wc -l)" "24"

check "dirty low"  "$(dirty_bytes_for low)"  "67108864 16777216"
check "dirty high" "$(dirty_bytes_for high)" "268435456 67108864"

SETTLE=15 MEASURE=90
check "cell seconds"    "$(cell_seconds)"       "130"
check "one rep"         "$(estimate_seconds 1)" "3120"
check "three reps"      "$(estimate_seconds 3)" "9360"
check "3 reps fit 5h"   "$(reps_that_fit 18000)" "5"
check "fmt_hms"         "$(fmt_hms 9360)"       "2h36m"
SETTLE=1 MEASURE=2

# PSI parsing against a fixture, so a kernel format change is caught here rather
# than as a column of zeroes in the results.
cat > "$TMP/io.pressure" <<'EOF'
some avg10=0.00 avg60=0.00 avg300=0.05 total=192418536
full avg10=0.00 avg60=0.00 avg300=0.04 total=153187155
EOF
check "psi some total" "$(psi_total "$TMP" io some)" "192418536"
check "psi full total" "$(psi_total "$TMP" io full)" "153187155"
check "psi missing file is empty" "$(psi_total "$TMP" nosuch some)" ""

check "hwmon absent name is empty" "$(hwmon_temp definitely-not-a-sensor)" ""

# diskstats must resolve the device and must be EMPTY, never 0, for a device
# that is not there: 0 would read as "no I/O happened".
check "diskstats reads nvme0n1" \
  "$([ -n "$(diskstat_sectors read)" ] && echo yes || echo no)" "yes"
check "diskstats write column too" \
  "$([ -n "$(diskstat_sectors write)" ] && echo yes || echo no)" "yes"

# Tool resolution has to work, because neither is installed in any profile here.
ensure_tools
check "python3 resolved" "$([ -x "${PY3:-}" ] && echo yes || echo no)" "yes"
check "fio resolved"     "$([ -x "${FIO:-}" ] && echo yes || echo no)" "yes"

# Every generated job must be syntactically valid to fio itself, not merely to
# me. --parse-only builds the job and exits without doing any I/O.
for p in "${PROFILE_LEVELS[@]}"; do
  mk_fio_job "$p" "$TMP/$p.fio"
  if "$FIO" --parse-only "$TMP/$p.fio" >/dev/null 2>&1; then
    echo "ok   - fio accepts the $p job"
  else
    echo "FAIL - fio rejects the $p job"
    "$FIO" --parse-only "$TMP/$p.fio" 2>&1 | head -3
    fail=1
  fi
done

# End to end on the smallest possible load: run a real job, parse its real JSON,
# and require the throughput columns to be populated. This is the check that
# would have caught a wrong JSON path or a renamed fio field.
echo "running a 3s fio job to verify real JSON parses..."
"$FIO" --name=smoke --directory="$TMP" --filename=smoke.bin --size=64M \
  --rw=randrw --rwmixread=70 --bs=4k --ioengine=psync --time_based --runtime=3 \
  --output-format=json --output="$TMP/smoke.json" >/dev/null 2>&1

row="$("$PY3" "$HERE/io-matrix-row.py" 1 kyber randrw low on \
  100 200 300 400 500 600 41.2 "$TMP/smoke.json" \
  '{"wakeups":900,"misses_120hz":2,"misses_60hz":0,"max_stall_ms":4.5,"wake_p50_us":10,"wake_p99_us":900,"wake_p999_us":1200,"reads":30,"read_p99_us":2500}')"

check "row has the full column count" \
  "$(echo "$row" | awk -F, '{print NF}')" \
  "$(echo "$CSV_HEADER" | awk -F, '{print NF}')"
check "fio read throughput parsed" \
  "$(echo "$row" | cut -d, -f13 | grep -cE '^[0-9]+\.[0-9]+$')" "1"
check "fio read iops parsed" \
  "$(echo "$row" | cut -d, -f15 | grep -cE '^[0-9]+\.[0-9]+$')" "1"
check "fio latency p99 parsed" \
  "$(echo "$row" | cut -d, -f18 | grep -cE '^[0-9]+\.[0-9]+$')" "1"
check "probe fields carried through" "$(echo "$row" | cut -d, -f20)" "2"

# A missing fio JSON must blank the columns, never zero them.
row2="$("$PY3" "$HERE/io-matrix-row.py" 1 kyber randrw low on \
  100 200 300 400 500 600 41.2 "$TMP/nonexistent.json" '{}')"
check "absent fio json blanks, not zeroes" "$(echo "$row2" | cut -d, -f13)" ""

# The analyzer must survive a real-shaped CSV.
{
  echo "$CSV_HEADER"
  for rep in 1 2; do
    for n in adios kyber; do
      for p in seqread randrw fsync; do
        for d in low high; do
          for i in on off; do
            "$PY3" "$HERE/io-matrix-row.py" "$rep" "$n" "$p" "$d" "$i" \
              1000 2000 1500 10 4096 2048 42.0 "$TMP/smoke.json" \
              '{"wakeups":900,"misses_120hz":1,"misses_60hz":0,"max_stall_ms":3.1,"wake_p50_us":10,"wake_p99_us":800,"wake_p999_us":1100,"reads":30,"read_p99_us":2000}'
          done
        done
      done
    done
  done
} > "$TMP/fake.csv"

if "$PY3" "$HERE/io-matrix-analyze.py" "$TMP/fake.csv" > "$TMP/an.txt" 2>&1; then
  echo "ok   - analyzer runs on a full-shaped csv"
else
  echo "FAIL - analyzer crashed"
  tail -15 "$TMP/an.txt"
  fail=1
fi
check "analyzer emits a verdict per profile" \
  "$(grep -c 'responsiveness:' "$TMP/an.txt")" "3"
check "analyzer never pools profiles" \
  "$(grep -c '^PROFILE ' "$TMP/an.txt")" "3"

exit "$fail"
