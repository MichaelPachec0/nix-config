"""Emit one CSV row for a one-factor A/B cell (sched-ab, iocost-ab).

argv: rep level psi_cpu psi_io psi_io_full psi_mem temp_c builds_alive probe_json

Every field is validated before it is printed. A row writer that can emit a
newline mid-row is not a cosmetic problem: `pgrep -c` prints 0 AND exits 1 when
nothing matches, so `$(pgrep -c ... || echo 0)` produced "0\\n0", which split
every line of a run in two. The analyzer then read the tail halves as data and
reported arm names of "0", "1" and "5". Fail the cell loudly instead.
"""

import json
import sys

FIELDS = ["misses_120hz", "misses_60hz", "max_stall_ms",
          "wake_p99_us", "wake_p999_us", "read_p99_us", "wakeups"]
EXPECTED_COLUMNS = 8 + len(FIELDS)


def clean(value, index):
    """Reject anything that would corrupt the CSV rather than silently writing it."""
    s = "" if value is None else str(value)
    if "\n" in s or "\r" in s:
        raise ValueError(
            "field %d contains a newline (%r). A shell helper is emitting more "
            "than one line -- `pgrep -c ... || echo 0` is the classic case."
            % (index, s))
    if "," in s:
        raise ValueError("field %d contains a comma (%r)" % (index, s))
    return s


def main():
    a = sys.argv[1:]
    if len(a) < 9:
        print("probe-row.py: expected 9 args, got %d" % len(a), file=sys.stderr)
        return 2
    head, probe_raw = a[:8], a[8]

    try:
        pr = json.loads(probe_raw) if probe_raw.strip() else {}
    except ValueError:
        pr = {}

    # Blank, never 0: a probe that failed to report and a probe that measured a
    # perfect window must not look the same in the results.
    cols = list(head) + ["" if pr.get(k) is None else pr[k] for k in FIELDS]

    try:
        cols = [clean(c, i) for i, c in enumerate(cols)]
    except ValueError as exc:
        print("probe-row.py: refusing to write a corrupt row: %s" % exc, file=sys.stderr)
        return 3

    if len(cols) != EXPECTED_COLUMNS:
        print("probe-row.py: built %d columns, header has %d"
              % (len(cols), EXPECTED_COLUMNS), file=sys.stderr)
        return 4

    print(",".join(cols))
    return 0


if __name__ == "__main__":
    sys.exit(main())
