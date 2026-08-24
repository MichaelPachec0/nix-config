"""Analyse an iocost-ab run.

One factor, so this is simpler than the matrix analysers, and it can afford to
be stricter. With every other factor held, the paired difference is between two
cells that differ in exactly one thing, and with 20 repetitions the question is
no longer "can this be resolved at all" but "how big is it".

read_p99_us is the primary metric and the reason the run exists: a desktop read
costs ~2.7ms on a quiet machine and ~19ms during a build. Everything else is
reported to catch a regression paid for that improvement.
"""

import csv
import statistics
import sys

PRIMARY = ("read_p99_us", "desktop's own read p99 -- THE metric this run exists for")
SECONDARY = [
    ("psi_io_us", "desktop us stalled on I/O"),
    ("max_stall_ms", "longest single stall"),
    ("wake_p999_us", "wakeup p99.9"),
    ("psi_cpu_us", "desktop us stalled on CPU"),
    ("psi_mem_us", "desktop us stalled on memory"),
]
# The cost side: if iocost slows builds, it shows up as fewer compilers alive at
# the end of the window.
COST = [("builds_alive", "compilers still running at window end (higher is better)")]

IDLE_READ_P99_US = 2696.0  # measured on a quiet machine, for scale


def num(row, key):
    try:
        return float(row[key])
    except (KeyError, ValueError, TypeError):
        return None


def paired(rows, metric):
    """(median, sd, n, [diffs]) of (on - off) across matched repetitions."""
    idx = {}
    for r in rows:
        v = num(r, metric)
        if v is None:
            continue
        idx.setdefault(r["rep"], {})[r["iocost"]] = v
    d = [c["on"] - c["off"] for c in idx.values() if "on" in c and "off" in c]
    if len(d) < 2:
        return None
    return statistics.median(d), statistics.pstdev(d), len(d), d


def report(rows, metric, label, higher_is_better=False):
    on = [v for v in (num(r, metric) for r in rows if r["iocost"] == "on") if v is not None]
    off = [v for v in (num(r, metric) for r in rows if r["iocost"] == "off") if v is not None]
    if not on or not off:
        return None
    got = paired(rows, metric)
    if got is None:
        return None
    med, sd, n, diffs = got
    mon, moff = statistics.median(on), statistics.median(off)
    resolvable = abs(med) > sd
    if higher_is_better:
        winner = "on" if med > 0 else "off"
    else:
        winner = "off" if med > 0 else "on"
    # A sign test alongside the spread rule: with one factor held against
    # everything else, consistency of direction is as informative as magnitude.
    wins = sum(1 for x in diffs if (x > 0) == higher_is_better and x != 0)
    tag = f"{winner} better" if resolvable else "noise"
    print(f"   {label}")
    print(f"     on={mon:,.1f}  off={moff:,.1f}   delta={med:+,.1f} sd={sd:,.1f} n={n}"
          f"   -> {tag}")
    print(f"     direction favoured 'on' in {wins}/{n} repetitions")
    return winner if resolvable else None


def main():
    rows = []
    for p in sys.argv[1:]:
        with open(p) as fh:
            rows.extend(list(csv.DictReader(fh)))
    if not rows:
        print("no rows", file=sys.stderr)
        return 1

    print(f"=== {' '.join(sys.argv[1:])} ===")
    print(f"{len(rows)} cells over {len({r['rep'] for r in rows})} repetitions")

    bad = [r for r in rows if str(r.get("builds_alive", "1")).strip() in ("0", "")]
    if bad:
        print(f"\n   WARNING: {len(bad)} row(s) had no compiler running at window end;")
        print("   the build finished early so part of that window measured an idle")
        print("   machine, which flatters whichever arm it landed on. Excluded.")
        rows = [r for r in rows if r not in bad]

    metric, label = PRIMARY
    print(f"\n-- PRIMARY: {label}")
    on = [v for v in (num(r, metric) for r in rows if r["iocost"] == "on") if v is not None]
    off = [v for v in (num(r, metric) for r in rows if r["iocost"] == "off") if v is not None]
    if on and off:
        print(f"   for scale, this machine idle: {IDLE_READ_P99_US:,.0f}us")
        print(f"   off is {statistics.median(off) / IDLE_READ_P99_US:.1f}x the idle cost,"
              f" on is {statistics.median(on) / IDLE_READ_P99_US:.1f}x")
        recovered = statistics.median(off) - statistics.median(on)
        gap = statistics.median(off) - IDLE_READ_P99_US
        if gap > 0:
            print(f"   iocost recovers {recovered:,.0f}us of the {gap:,.0f}us gap"
                  f" = {100 * recovered / gap:.0f}% of what a quiet machine would give")
    winner = report(rows, metric, "paired")

    print("\n-- SECONDARY: is anything else made worse to pay for it")
    for m, l in SECONDARY:
        report(rows, m, l)

    print("\n-- COST: what it takes from the build")
    for m, l in COST:
        report(rows, m, l, higher_is_better=True)

    print("\n-- frame deadlines. Zero-inflated counts, so totals and affected-cell")
    print("   splits rather than a paired median, which would be structurally 0.")
    for m in ("misses_120hz", "misses_60hz"):
        parts = []
        for lv in ("on", "off"):
            vals = [int(num(r, m) or 0) for r in rows if r["iocost"] == lv]
            hit = sum(1 for v in vals if v)
            parts.append(f"{lv}={sum(vals)} in {hit}/{len(vals)} cells")
        print(f"   {m:14s} " + "   ".join(parts))

    print("\n-- VERDICT")
    if winner == "on":
        print("   iocost resolvably improves the read tail. Adopt it only if the")
        print("   COST line above shows builds are not paying an unacceptable price.")
    elif winner == "off":
        print("   iocost makes the read tail WORSE. Do not adopt.")
    else:
        print("   No resolvable effect on the metric this run exists for. That is the")
        print("   same answer ioprio and io.latency gave, and it means the read tail")
        print("   during a build is not a cgroup I/O-prioritisation problem. Look at")
        print("   the device queue itself, or accept it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
