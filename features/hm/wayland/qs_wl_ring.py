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
# Pure decision helpers live in ring_lines(); ./qs_wl_ring_test.py covers them.
import collections
import os
import sys
import time

DEFAULT_LINES = 200000
SNAPSHOT_SEC = 30


def ring_lines(lines, limit):
    """The last `limit` items of `lines`, oldest first."""
    return list(collections.deque(lines, maxlen=limit))


def dump(ring, path):
    """Atomically replace `path` with the ring's contents."""
    tmp = path + ".tmp"
    with open(tmp, "w") as handle:
        handle.writelines(ring)
    os.replace(tmp, path)


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.expanduser("~/qs-wl-tail.log")
    limit = int(argv[2]) if len(argv) > 2 else DEFAULT_LINES

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
