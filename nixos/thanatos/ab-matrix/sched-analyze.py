"""Analyse a sched-ab run: scx_flash against EEVDF-BORE against plain EEVDF.

Three arms measured in one boot, so all three pairwise comparisons are paired
on the repetition and none of them has to be made across a kernel change.

The primary metrics are the two that separated flash from EEVDF last time:
missed 120Hz frame deadlines (flash 3, eevdf 22) and wakeup p99.9 (flash
1074us, eevdf 1629us). Frame misses are a zero-inflated count, so they get
totals and affected-cell splits rather than a paired median, which would be
structurally zero and would report noise no matter how lopsided the totals.
"""

import csv
import itertools
import statistics
import sys

CONTINUOUS = [
    # BOTH wakeup statistics, because they disagree and the disagreement is the
    # result. scx_flash flattens the whole distribution: its p99 and p99.9 sit
    # within 80us of each other, so nearly every wakeup costs about a
    # millisecond. BORE is far faster typically and gives that back at the
    # extreme. Reporting only p99.9 -- which is what the first version of this
    # file did, because p99.9 was what separated flash from plain EEVDF -- picks
    # flash while hiding a 2.6x difference in what a wakeup usually costs.
    ("wake_p99_us", "lower", "wakeup p99 -- what a wakeup USUALLY costs"),
    ("wake_p999_us", "lower", "wakeup p99.9 -- the extreme tail"),
    ("max_stall_ms", "lower", "longest single stall"),
    ("psi_cpu_us", "lower", "desktop us stalled on CPU"),
    ("read_p99_us", "lower", "desktop's own read p99"),
    ("psi_io_us", "lower", "desktop us stalled on I/O"),
    ("psi_mem_us", "lower", "desktop us stalled on memory"),
]
COUNTS = [("misses_120hz", "missed 120Hz frame deadlines -- PRIMARY"),
          ("misses_60hz", "missed 60Hz frame deadlines")]
COST = ("builds_alive", "compilers alive at window end (higher is better)")

# Measured on the previous kernel, for orientation only. Never compared against
# directly: that kernel had no BORE in it and these arms are a different build.
PRIOR = "prior run, different kernel: flash wake_p999 1074us / 3 misses, eevdf 1629us / 22"


def num(row, key):
    try:
        return float(row[key])
    except (KeyError, ValueError, TypeError):
        return None


def paired(rows, a, b, metric):
    idx = {}
    for r in rows:
        v = num(r, metric)
        if v is None:
            continue
        idx.setdefault(r["rep"], {})[r["sched"]] = v
    d = [c[a] - c[b] for c in idx.values() if a in c and b in c]
    if len(d) < 2:
        return None
    return statistics.median(d), statistics.pstdev(d), len(d), d


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
    print(f"   {PRIOR}")

    bad = [r for r in rows if str(r.get("builds_alive", "1")).strip() in ("0", "")]
    if bad:
        print(f"\n   WARNING: {len(bad)} row(s) had no compiler running at window end;")
        print("   the build finished early so part of that window measured an idle")
        print("   machine. Excluded.")
        rows = [r for r in rows if r not in bad]

    arms = sorted({r["sched"] for r in rows})
    print(f"\n   arms present: {', '.join(arms)}")
    for a in arms:
        n = len([r for r in rows if r["sched"] == a])
        print(f"     {a:6s} {n} cells")

    print("\n" + "=" * 72)
    print("FRAME DEADLINES (primary; counts, so totals not medians)")
    print("=" * 72)
    for metric, label in COUNTS:
        print(f"\n-- {label}")
        for a in arms:
            vals = [int(num(r, metric) or 0) for r in rows if r["sched"] == a]
            hit = sum(1 for v in vals if v)
            worst = max(vals) if vals else 0
            print(f"   {a:6s} {sum(vals):4d} misses in {hit:2d}/{len(vals):2d} cells,"
                  f" worst cell {worst}")

    print("\n" + "=" * 72)
    print("CONTINUOUS METRICS, all three pairwise comparisons")
    print("=" * 72)
    winners = {}
    for metric, direction, label in CONTINUOUS:
        print(f"\n-- {label}")
        for a in arms:
            vals = [v for v in (num(r, metric) for r in rows if r["sched"] == a)
                    if v is not None]
            if vals:
                print(f"   {a:6s} median={statistics.median(vals):>12,.1f}"
                      f"   min={min(vals):>10,.1f}  max={max(vals):>12,.1f}")
        for a, b in itertools.combinations(arms, 2):
            got = paired(rows, a, b, metric)
            if got is None:
                continue
            med, sd, n, _ = got
            if abs(med) > sd:
                win = (b if med > 0 else a) if direction == "lower" else (a if med > 0 else b)
                tag = f"{win} better"
                winners.setdefault(metric, []).append((a, b, win))
            else:
                tag = "noise"
            print(f"     {a} vs {b}: delta={med:+,.1f} sd={sd:,.1f} n={n} -> {tag}")

    print("\n" + "=" * 72)
    print("COST TO THE BUILD")
    print("=" * 72)
    metric, label = COST
    print(f"\n-- {label}")
    for a in arms:
        vals = [v for v in (num(r, metric) for r in rows if r["sched"] == a) if v is not None]
        if vals:
            print(f"   {a:6s} median={statistics.median(vals):.1f}")
    for a, b in itertools.combinations(arms, 2):
        got = paired(rows, a, b, metric)
        if got is None:
            continue
        med, sd, n, _ = got
        tag = ((a if med > 0 else b) + " better") if abs(med) > sd else "noise"
        print(f"     {a} vs {b}: delta={med:+,.1f} sd={sd:,.1f} n={n} -> {tag}")

    print("\n" + "=" * 72)
    print("VERDICT")
    print("=" * 72)
    m120 = {a: sum(int(num(r, "misses_120hz") or 0) for r in rows if r["sched"] == a)
            for a in arms}
    print(f"\n  120Hz misses: " + "   ".join(f"{a}={m120[a]}" for a in arms))
    tally = {a: 0 for a in arms}
    for lst in winners.values():
        for _, _, w in lst:
            tally[w] = tally.get(w, 0) + 1
    print(f"  resolvable continuous wins: " + "   ".join(f"{a}={tally.get(a, 0)}" for a in arms))

    if "flash" in arms and "bore" in arms:
        a99 = paired(rows, "flash", "bore", "wake_p99_us")
        a999 = paired(rows, "flash", "bore", "wake_p999_us")
        if a99 and a999 and (a99[0] > 0) != (a999[0] > 0):
            print("\n  The two wakeup statistics DISAGREE, which is the finding rather")
            print("  than a problem: one arm is better typically and the other at the")
            print("  extreme. Judge them against the frame budget -- 8333us at 120Hz --")
            print("  rather than against each other. A tail that is already an order of")
            print("  magnitude under the budget cannot be felt, while a difference in")
            print("  what a wakeup usually costs applies to every wakeup there is.")

    if "bore" in arms and "eevdf" in arms:
        got = paired(rows, "bore", "eevdf", "wake_p999_us")
        if got and abs(got[0]) <= got[1]:
            print("\n  bore vs eevdf is noise on the primary continuous metric, and both")
            print("  ran on the same kernel in the same boot. If their frame-miss totals")
            print("  are also close, BORE is not doing anything measurable here and the")
            print("  real comparison is simply scx_flash against the fair class.")
    best = min(m120, key=lambda a: m120[a]) if m120 else None
    if best is not None and list(m120.values()).count(m120[best]) == 1:
        print(f"\n  Fewest dropped frames: {best}. Weigh that against the continuous")
        print("  tally and the build cost above before changing memory.nix.")
    else:
        print("\n  No arm is cleanly ahead on dropped frames; decide on the continuous")
        print("  metrics and the build cost, and keep the incumbent if those tie.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
