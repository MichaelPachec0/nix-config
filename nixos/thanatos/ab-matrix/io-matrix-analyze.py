"""Analyse an io-matrix run: adios against kyber under real queue pressure.

Two rules shape this file.

RESPONSIVENESS FIRST. Throughput is reported in full, but it never decides.
Where the two disagree the disagreement is printed explicitly and the stated
rule is applied rather than quietly split.

NEVER POOL ACROSS PROFILES. seqread MB/s and fsync commit latency are different
quantities; averaging them produces a number that describes nothing. Every
scheduler comparison here is made inside one profile, against cells that differ
in the scheduler alone.

Comparisons are PAIRED: cells identical in every other factor, differenced, then
the median and spread of those differences. Pooling a level's raw values instead
inflates its apparent noise floor by whatever the largest OTHER effect happens
to be, which is how a real 100us effect hides behind an unrelated 580us one.
"""

import csv
import itertools
import statistics
import sys

FACTORS = ["nvme", "profile", "dirty", "iolat"]

# (column, direction, label). Responsiveness only -- what the desktop felt.
RESP = [
    ("psi_io_us", "lower", "desktop us stalled on I/O"),
    ("read_p99_us", "lower", "desktop's own read p99"),
    ("max_stall_ms", "lower", "longest single stall"),
    ("wake_p999_us", "lower", "wakeup p99.9"),
    ("psi_cpu_us", "lower", "desktop us stalled on CPU"),
]

# The load's own numbers. Higher is better for the first four.
PERF = [
    ("fio_read_mbps", "higher", "load read throughput MB/s"),
    ("fio_write_mbps", "higher", "load write throughput MB/s"),
    ("fio_read_iops", "higher", "load read IOPS"),
    ("fio_write_iops", "higher", "load write IOPS"),
    ("fio_lat_p99_us", "lower", "load's own latency p99"),
    ("fio_lat_p999_us", "lower", "load's own latency p99.9"),
]

COUNTS = [("misses_120hz", "missed 120Hz frame deadlines"),
          ("misses_60hz", "missed 60Hz frame deadlines")]


def num(row, key):
    try:
        return float(row[key])
    except (KeyError, ValueError, TypeError):
        return None


def paired(rows, factor, a, b, metric, within=None):
    """Median and spread of (a - b) over cells identical in every other factor."""
    others = [f for f in FACTORS if f != factor] + ["rep"]
    index = {}
    for r in rows:
        if within and r["profile"] != within:
            continue
        v = num(r, metric)
        if v is None:
            continue
        index.setdefault(tuple(r[g] for g in others), {})[r[factor]] = v
    diffs = [c[a] - c[b] for c in index.values() if a in c and b in c]
    if len(diffs) < 2:
        return None
    return statistics.median(diffs), statistics.pstdev(diffs), len(diffs)


def verdict(med, sd, direction, a, b):
    """(resolvable, winner). |median| must clear one standard deviation."""
    if abs(med) <= sd:
        return False, None
    if direction == "lower":
        return True, (b if med > 0 else a)
    return True, (a if med > 0 else b)


def level_median(rows, factor, level, metric, within=None):
    vals = [v for v in (num(r, metric) for r in rows
                        if r[factor] == level and (not within or r["profile"] == within))
            if v is not None]
    return statistics.median(vals) if vals else None


def compare_block(rows, factor, a, b, metrics, within, indent="   "):
    """Print one factor's comparison, return {metric: winner-or-None}."""
    won = {}
    for metric, direction, label in metrics:
        ma = level_median(rows, factor, a, metric, within)
        mb = level_median(rows, factor, b, metric, within)
        if ma is None or mb is None:
            continue
        got = paired(rows, factor, a, b, metric, within)
        if got is None:
            continue
        med, sd, n = got
        ok, winner = verdict(med, sd, direction, a, b)
        won[metric] = winner
        tag = f"{winner} better" if ok else "noise"
        print(f"{indent}{label:28s} {a}={ma:>12,.1f}  {b}={mb:>12,.1f}"
              f"   delta={med:+,.1f} sd={sd:,.1f} n={n} -> {tag}")
    return won


def main():
    rows = []
    for p in sys.argv[1:]:
        with open(p) as fh:
            rows.extend(list(csv.DictReader(fh)))
    if not rows:
        print("no rows", file=sys.stderr)
        return 1

    print(f"=== {' '.join(sys.argv[1:])} ===")
    print(f"{len(rows)} cells, reps {sorted({r['rep'] for r in rows})}")

    # Did the load actually load the device? This is the check the previous
    # matrix could not make, and the reason its I/O conclusions were scoped to
    # "during a build" rather than "under I/O pressure".
    print("\n-- device traffic per cell, from /proc/diskstats (ground truth,")
    print("   independent of what fio thought it wrote through compress-force)")
    for prof in sorted({r["profile"] for r in rows}):
        sel = [r for r in rows if r["profile"] == prof]
        rd = [num(r, "dev_read_mb") for r in sel]
        wr = [num(r, "dev_write_mb") for r in sel]
        rd = [x for x in rd if x is not None]
        wr = [x for x in wr if x is not None]
        if not rd:
            continue
        dur = 90.0
        print(f"   {prof:8s} read {statistics.median(rd):8,.0f} MB "
              f"({statistics.median(rd)/dur:7,.0f} MB/s)   "
              f"write {statistics.median(wr):8,.0f} MB "
              f"({statistics.median(wr)/dur:7,.0f} MB/s)")
    # A read profile whose device traffic falls well short of what fio asked
    # for was answered from page cache, which means the scheduler under test
    # never saw those requests and a "tie" for that profile is weak evidence
    # rather than a finding. Say so rather than leaving it to be spotted.
    for prof in sorted({r["profile"] for r in rows}):
        sel = [r for r in rows if r["profile"] == prof]
        fr = [x for x in (num(r, "fio_read_mbps") for r in sel) if x]
        dr = [x for x in (num(r, "dev_read_mb") for r in sel) if x]
        if not fr or not dr:
            continue
        asked, got = statistics.median(fr), statistics.median(dr) / 90.0
        if asked > 10 and got < 0.7 * asked:
            print(f"   WARNING: {prof} asked for {asked:,.0f} MB/s but the device "
                  f"delivered {got:,.0f};")
            print(f"            {100 * (1 - got / asked):.0f}% came from page cache, so the queue was "
                  "under-pressured.")
            print("            Raise WORKSET_GB and re-run before trusting this profile.")

    tot_w = sum(x for x in (num(r, "dev_write_mb") for r in rows) if x)
    print(f"   total written this run: {tot_w/1024:,.1f} GB")

    print("\n-- write amplification: what fio asked the filesystem for against what")
    print("   reached the device. /home is compress-force=zstd:1 CoW btrfs on LUKS,")
    print("   so these are not the same number and the gap is the filesystem's cost.")
    for prof in sorted({r["profile"] for r in rows}):
        sel = [r for r in rows if r["profile"] == prof]
        fw = [x for x in (num(r, "fio_write_mbps") for r in sel) if x]
        dw = [x for x in (num(r, "dev_write_mb") for r in sel) if x]
        if not fw or not dw or statistics.median(fw) < 1:
            continue
        asked, got = statistics.median(fw), statistics.median(dw) / 90.0
        print(f"   {prof:8s} fio {asked:7,.1f} MB/s -> device {got:7,.1f} MB/s "
              f"= {got/asked:5.1f}x")

    temps = [x for x in (num(r, "dev_temp_c") for r in rows) if x is not None]
    if temps:
        print(f"\n   drive temp: min {min(temps):.1f}C  median "
              f"{statistics.median(temps):.1f}C  max {max(temps):.1f}C"
              "   (a rising max means thermal throttling is in the results)")

    profiles = sorted({r["profile"] for r in rows})
    scheds = sorted({r["nvme"] for r in rows})
    if len(scheds) != 2:
        print(f"\nexpected exactly 2 schedulers, got {scheds}", file=sys.stderr)
        return 1
    a, b = scheds

    resp_winners, perf_winners = {}, {}

    for prof in profiles:
        print(f"\n{'=' * 72}\nPROFILE {prof}\n{'=' * 72}")

        print(f"\n-- RESPONSIVENESS (primary): {a} vs {b}")
        rw = compare_block(rows, "nvme", a, b, RESP, prof)

        print(f"\n-- frame-deadline misses. Zero-inflated counts: most cells score")
        print("   0, so a paired MEDIAN is structurally 0 and reports noise however")
        print("   lopsided the totals. Compared as totals and affected-cell splits.")
        for metric, label in COUNTS:
            parts = []
            for lv in scheds:
                vals = [int(num(r, metric) or 0) for r in rows
                        if r["profile"] == prof and r["nvme"] == lv]
                hit = sum(1 for v in vals if v)
                parts.append(f"{lv}={sum(vals)} in {hit}/{len(vals)} cells")
            print(f"   {label:32s} " + "   ".join(parts))

        print(f"\n-- RAW PERFORMANCE (secondary): {a} vs {b}")
        pw = compare_block(rows, "nvme", a, b, PERF, prof)

        # Tally. A scheduler wins the category if it takes strictly more of the
        # resolvable metrics in it.
        def tally(won):
            c = {a: 0, b: 0}
            for w in won.values():
                if w in c:
                    c[w] += 1
            if c[a] > c[b]:
                return a, c
            if c[b] > c[a]:
                return b, c
            return None, c

        rwin, rc = tally(rw)
        pwin, pc = tally(pw)
        miss = {lv: sum(int(num(r, "misses_120hz") or 0) for r in rows
                        if r["profile"] == prof and r["nvme"] == lv) for lv in scheds}
        resp_winners[prof] = (rwin, rc, miss)
        perf_winners[prof] = (pwin, pc)

    print(f"\n{'=' * 72}\nVERDICT -- responsiveness first, throughput second\n{'=' * 72}")
    for prof in profiles:
        rwin, rc, miss = resp_winners[prof]
        pwin, pc = perf_winners[prof]
        rtxt = f"{rwin}" if rwin else "tie"
        ptxt = f"{pwin}" if pwin else "tie"
        print(f"\n  {prof}")
        print(f"    responsiveness: {rtxt:6s} ({rc[a]} resolvable to {a}, {rc[b]} to {b}; "
              f"120Hz misses {a}={miss[a]} {b}={miss[b]})")
        print(f"    throughput:     {ptxt:6s} ({pc[a]} resolvable to {a}, {pc[b]} to {b})")
        if rwin and pwin and rwin != pwin:
            print(f"    -> DISAGREE. {rwin} keeps the desktop better, {pwin} moves more")
            print(f"       data. Rule says responsiveness first, so: {rwin}.")
        elif rwin:
            print(f"    -> {rwin}" + (f", and it also wins throughput." if pwin == rwin
                                      else ", throughput undecided."))
        elif pwin:
            print(f"    -> responsiveness undecided; throughput favours {pwin}. A tie on")
            print("       the primary criterion is a real result: pick on the secondary.")
        else:
            print("    -> undecided on both. Under this load the two are equivalent.")

    # The other two factors, pooled across profiles because they are not
    # scheduler-specific and their levels mean the same thing everywhere.
    print(f"\n{'=' * 72}\nOTHER FACTORS (all profiles)\n{'=' * 72}")
    for factor, la, lb in (("iolat", "on", "off"), ("dirty", "high", "low")):
        levels = sorted({r[factor] for r in rows})
        if len(levels) != 2:
            continue
        print(f"\n-- {factor}: {la} vs {lb}")
        compare_block(rows, factor, la, lb, RESP, None)
        for metric, label in COUNTS:
            parts = []
            for lv in levels:
                vals = [int(num(r, metric) or 0) for r in rows if r[factor] == lv]
                hit = sum(1 for v in vals if v)
                parts.append(f"{lv}={sum(vals)} in {hit}/{len(vals)} cells")
            print(f"   {label:32s} " + "   ".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
