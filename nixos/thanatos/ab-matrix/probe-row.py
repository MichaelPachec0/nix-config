"""Emit one CSV row for an iocost-ab cell.

argv: rep iocost psi_cpu psi_io psi_io_full psi_mem temp_c builds_alive probe_json
"""

import json
import sys

FIELDS = ["misses_120hz", "misses_60hz", "max_stall_ms",
          "wake_p99_us", "wake_p999_us", "read_p99_us", "wakeups"]


def main():
    a = sys.argv[1:]
    if len(a) < 9:
        print("iocost-row.py: expected 9 args, got %d" % len(a), file=sys.stderr)
        return 2
    head, probe_raw = a[:8], a[8]
    try:
        pr = json.loads(probe_raw) if probe_raw.strip() else {}
    except ValueError:
        pr = {}
    # Blank, never 0: a probe that failed to report and a probe that measured a
    # perfect window must not look the same in the results.
    print(",".join(list(head) + [
        "" if pr.get(k) is None else str(pr[k]) for k in FIELDS]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
