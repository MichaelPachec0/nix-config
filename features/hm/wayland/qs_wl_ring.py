# Ring-buffer stdin to a file, and write it out when the producer dies.
#
# WAYLAND_DEBUG is tens of thousands of lines a minute and the interesting
# window is the last second before the client is destroyed, so a plain file is
# too big and `tail` loses its buffer with the pipe. Keep the last N lines in
# memory and flush on stdin EOF, which is what a client calling _exit(1)
# produces on the write end.
#
# Also snapshots on a timer, so a kill -9 of THIS process still leaves the bulk
# of the evidence on disk. Writes are tmp + rename, so an interrupted snapshot
# never truncates the previous one.
#
# ONE FILE PER PRODUCER LIFETIME, not one file overall. The bar is relaunched
# seconds after it dies, so on a single fixed path the new reader's first
# snapshot destroys the crash trace before anyone reads it; two crashes in a
# row left only the second. The name carries the producer's START time (the
# snapshots need a stable target from line one); crash time is the last line's
# own timestamp, inside the file. Both UTC. The pid suffix stops two launches
# in the same second colliding. `<base>` stays a symlink to the current run.
#
# Pure decision helpers live in ring_lines(), run_path() and prunable();
# ./qs_wl_ring_test.py covers them.
import collections
import glob
import os
import sys
import time

DEFAULT_LINES = 200000
SNAPSHOT_SEC = 30
# A full 200k-line ring is ~14 MB, so this is a ~140 MB ceiling. Raise via
# QS_WL_KEEP when chasing something that needs a long history of runs.
DEFAULT_KEEP = 10


def ring_lines(lines, limit):
    """The last `limit` items of `lines`, oldest first."""
    return list(collections.deque(lines, maxlen=limit))


def run_path(base, stamp, pid):
    """Per-run log path: `<stem>-<stamp>-<pid><ext>` beside `base`.

    Fixed-width stamp leads, so lexical sort == chronological sort; prunable()
    relies on that.
    """
    stem, ext = os.path.splitext(base)
    return "%s-%s-%d%s" % (stem, stamp, pid, ext or ".log")


def run_glob(base):
    """Shell glob matching every run file that run_path() can produce."""
    stem, ext = os.path.splitext(base)
    return "%s-*-*%s" % (stem, ext or ".log")


def prunable(paths, keep):
    """Which of `paths` to delete so at most `keep` newest remain, oldest first.

    keep <= 0 disables pruning rather than deleting everything: losing the run
    in progress is the one unrecoverable outcome.
    """
    if keep <= 0 or len(paths) <= keep:
        return []
    return sorted(paths)[: len(paths) - keep]


def dump(ring, path):
    """Atomically replace `path` with the ring's contents."""
    tmp = path + ".tmp"
    with open(tmp, "w") as handle:
        handle.writelines(ring)
    os.replace(tmp, path)


def link_current(base, target):
    """Point `base` at `target` (same dir), replacing what was there.

    Symlink not copy: the run file is rewritten every 30s. tmp + os.replace so
    `base` is never briefly missing; something may be tailing it.
    """
    tmp = base + ".link.tmp"
    if os.path.lexists(tmp):
        os.remove(tmp)
    os.symlink(os.path.basename(target), tmp)
    os.replace(tmp, base)


def main(argv):
    base = argv[1] if len(argv) > 1 else os.path.expanduser("~/qs-wl-tail.log")
    limit = int(argv[2]) if len(argv) > 2 else DEFAULT_LINES
    keep = int(os.environ.get("QS_WL_KEEP", DEFAULT_KEEP))

    path = run_path(base, time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), os.getpid())

    # Create before linking so `base` is never dangling; prune before writing so
    # the ceiling counts this run.
    dump([], path)
    for stale in prunable(glob.glob(run_glob(base)), keep):
        if stale != path:
            os.remove(stale)
    link_current(base, path)

    ring = collections.deque(maxlen=limit)
    last = time.monotonic()
    for line in sys.stdin:
        ring.append(line)
        now = time.monotonic()
        if now - last >= SNAPSHOT_SEC:
            dump(ring, path)
            last = now
    # EOF: the producer is gone. This is the write that matters.
    dump(ring, path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
