"""Emit one CSV row for an io-matrix cell.

Kept out of the shell script because parsing fio's JSON with awk is how a
benchmark quietly starts recording zeroes. Every field that cannot be read is
emitted EMPTY, never 0: "the counter was missing" and "the load did nothing"
must not look the same in the results.

argv: rep nvme profile dirty iolat psi_cpu psi_io psi_io_full psi_mem
      dev_read_mb dev_write_mb dev_temp_c fio_json_path probe_json
"""

import json
import sys


def jload(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def pct(node, key):
    """clat/lat percentile in microseconds, or None. fio reports nanoseconds."""
    try:
        p = node["percentile"]
    except (KeyError, TypeError):
        return None
    # fio spells these "50.000000"; match on the numeric value so a formatting
    # change upstream does not silently blank the column.
    want = float(key)
    for k, v in p.items():
        try:
            if abs(float(k) - want) < 1e-6:
                return v / 1000.0
        except ValueError:
            continue
    return None


def fio_stats(doc, profile):
    """(read_mbps, write_mbps, read_iops, write_iops, p50, p99, p999).

    The three latency columns are the load's OWN completion latency for the
    direction that dominates the profile: reads for seqread and randrw (70/30),
    and the durable-commit latency for fsync, which is the number that profile
    exists to measure. Comparing them across profiles is meaningless; the
    analyze pass only ever compares within one.
    """
    empty = ("", "", "", "", "", "", "")
    if not doc:
        return empty
    jobs = doc.get("jobs") or []
    if not jobs:
        return empty
    j = jobs[0]  # group_reporting=1 collapses numjobs into one entry
    rd, wr = j.get("read") or {}, j.get("write") or {}

    def mbps(node):
        bw = node.get("bw")  # KiB/s
        return "" if bw is None else round(bw / 1024.0, 1)

    def iops(node):
        v = node.get("iops")
        return "" if v is None else round(v, 1)

    if profile == "fsync":
        src = (j.get("sync") or {}).get("lat_ns") or wr.get("clat_ns") or {}
    else:
        src = rd.get("clat_ns") or {}
    p50, p99, p999 = (pct(src, "50.0"), pct(src, "99.0"), pct(src, "99.9"))
    fmt = lambda v: "" if v is None else round(v, 1)
    return (mbps(rd), mbps(wr), iops(rd), iops(wr), fmt(p50), fmt(p99), fmt(p999))


def main():
    a = sys.argv[1:]
    if len(a) < 14:
        print("io-matrix-row.py: expected 14 args, got %d" % len(a), file=sys.stderr)
        return 2
    (rep, nvme, profile, dirty, iolat, pcpu, pio, piof, pmem,
     rdmb, wrmb, temp, fiopath) = a[:13]
    probe_raw = a[13]

    fr, fw, fri, fwi, p50, p99, p999 = fio_stats(jload(fiopath), profile)

    try:
        pr = json.loads(probe_raw) if probe_raw.strip() else {}
    except ValueError:
        pr = {}

    def g(k):
        v = pr.get(k)
        return "" if v is None else v

    cols = [rep, nvme, profile, dirty, iolat,
            pcpu, pio, piof, pmem, rdmb, wrmb, temp,
            fr, fw, fri, fwi, p50, p99, p999,
            g("misses_120hz"), g("misses_60hz"), g("max_stall_ms"),
            g("wake_p99_us"), g("wake_p999_us"), g("read_p99_us"), g("wakeups")]
    print(",".join(str(c) for c in cols))
    return 0


if __name__ == "__main__":
    sys.exit(main())
