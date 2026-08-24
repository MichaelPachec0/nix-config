"""Desktop-responsiveness probe. Runs INSIDE user.slice while a build loads the
machine, and reports what a compositor would actually have experienced.

Why deadline misses rather than a latency percentile: perception is
threshold-shaped. Two hundred frames arriving at 9ms are invisible; one 300ms
stall is the complaint. A percentile averages the events you care about into the
ones you do not, which is exactly how a p99 can improve while the desktop feels
worse.

Why it also reads from disk: io.latency on user.slice only throttles peer
cgroups when user.slice itself is doing I/O and missing its latency target. A
probe that only sleeps would leave that mechanism dormant and make the iolat
factor unmeasurable -- which is precisely the flaw that made the fio-based
matrix report iolat as noise.

Emits one JSON object on stdout.
"""

import json
import os
import random
import sys
import time

FRAME_S = 1.0 / 120.0        # target cadence: 120Hz, this panel's refresh
MISS_1F = 1.0 / 120.0 * 1.5  # late enough that a 120Hz frame is at risk
MISS_60 = 1.0 / 60.0         # a 60Hz frame deadline: unambiguously visible
READ_EVERY = 24              # ~5 reads/sec, enough to keep io.latency engaged
READ_SZ = 4096


def main() -> int:
    dur = float(sys.argv[1])
    path = sys.argv[2] if len(sys.argv) > 2 else ""

    fd = -1
    fsize = 0
    if path and os.path.exists(path):
        fd = os.open(path, os.O_RDONLY)
        fsize = os.fstat(fd).st_size

    overshoot = []       # microseconds late per wakeup
    read_us = []
    misses_1f = 0
    misses_60 = 0
    max_stall_us = 0.0
    rng = random.Random(1234)   # fixed seed: same access pattern every cell
    i = 0

    end = time.monotonic() + dur
    while time.monotonic() < end:
        t0 = time.monotonic()
        time.sleep(FRAME_S)
        late = (time.monotonic() - t0 - FRAME_S) * 1e6
        if late < 0:
            late = 0.0
        overshoot.append(late)
        if late > max_stall_us:
            max_stall_us = late
        if late >= (MISS_1F - FRAME_S) * 1e6:
            misses_1f += 1
        if late >= (MISS_60 - FRAME_S) * 1e6:
            misses_60 += 1

        i += 1
        if fd >= 0 and i % READ_EVERY == 0 and fsize > READ_SZ:
            off = rng.randrange(0, fsize - READ_SZ) & ~0xFFF
            # Drop this range from cache first, so the read actually reaches the
            # device. Without it the page cache would answer and the probe would
            # generate no I/O for io.latency to act on.
            try:
                os.posix_fadvise(fd, off, READ_SZ, os.POSIX_FADV_DONTNEED)
            except OSError:
                pass
            r0 = time.monotonic()
            try:
                os.pread(fd, READ_SZ, off)
                read_us.append((time.monotonic() - r0) * 1e6)
            except OSError:
                pass

    if fd >= 0:
        os.close(fd)

    def pct(xs: list[float], p: float) -> float:
        if not xs:
            return 0.0
        s = sorted(xs)
        return s[min(len(s) - 1, int(len(s) * p))]

    json.dump({
        "wakeups": len(overshoot),
        "misses_120hz": misses_1f,
        "misses_60hz": misses_60,
        "max_stall_ms": round(max_stall_us / 1000.0, 2),
        "wake_p50_us": round(pct(overshoot, 0.50), 1),
        "wake_p99_us": round(pct(overshoot, 0.99), 1),
        "wake_p999_us": round(pct(overshoot, 0.999), 1),
        "reads": len(read_us),
        "read_p99_us": round(pct(read_us, 0.99), 1),
    }, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
