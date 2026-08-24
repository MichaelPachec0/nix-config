"""Populate page cache for a list of files, and verify it worked.

read(2), not posix_fadvise(WILLNEED). WILLNEED is advisory and plateaued at
40% of a 160 MB corpus here regardless of concurrency. read reaches 100%.

4 workers is measured: 722 -> 1469 MB/s from 1 reader to 4, then it degrades
as decompression competes with the readers for cores.
"""

from __future__ import annotations

import ctypes
import ctypes.util
import os

_libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
_libc.mmap.restype = ctypes.c_void_p
_libc.mmap.argtypes = [
    ctypes.c_void_p,
    ctypes.c_size_t,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_long,
]
_libc.munmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
_libc.mincore.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p]

PAGE = os.sysconf("SC_PAGE_SIZE")
_PROT_READ = 1
_MAP_PRIVATE = 2
_MAP_FAILED = ctypes.c_void_p(-1).value
READ_CHUNK = 1 << 20


def resident(path: str) -> tuple[int, int]:
    """Return (bytes of path in page cache, file size).

    UNRELIABLE on /nix: mincore reports every page present, always, rc=0
    errno=0 vector all 1s, even for files never read this boot and even
    while a read still pulls the full compressed content off the device.
    Correct on /tmp and /home in the same process. Use device_read_bytes()
    as the oracle for whether a read actually touched the disk.

    Maps via libc: a PROT_READ mmap object is not a writable buffer, so
    ctypes cannot take its address.
    """
    try:
        size = os.path.getsize(path)
        if size == 0:
            return 0, 0
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return 0, 0
    addr = None
    try:
        addr = _libc.mmap(None, size, _PROT_READ, _MAP_PRIVATE, fd, 0)
        if addr is None or addr == _MAP_FAILED:
            return 0, size
        npages = (size + PAGE - 1) // PAGE
        vec = ctypes.create_string_buffer(npages)
        if _libc.mincore(ctypes.c_void_p(addr), ctypes.c_size_t(size), vec) != 0:
            return 0, size
        present = sum(1 for b in vec.raw[:npages] if b & 1)
        # Final page counts whole but is usually partial.
        return min(present * PAGE, size), size
    finally:
        if addr is not None and addr != _MAP_FAILED:
            _libc.munmap(ctypes.c_void_p(addr), size)
        os.close(fd)


def device_read_bytes() -> int:
    """Bytes read from real block devices since boot.

    Sums field 3 of /sys/block/*/stat (sectors read) x512 for devices that
    have a `device` symlink, i.e. real hardware. Excludes dm-*, loop* and
    zram0, whose traffic the whole-disk counters already include -- a read
    through dm-crypt shows up identically on dm-2 and nvme0n1, so summing
    both would double count.

    This is the honest oracle for "did that read actually touch the disk".
    mincore cannot answer it on /nix.
    """
    total = 0
    try:
        names = os.listdir("/sys/block")
    except OSError:
        return 0
    for name in names:
        base = os.path.join("/sys/block", name)
        if not os.path.exists(os.path.join(base, "device")):
            continue
        try:
            with open(os.path.join(base, "stat"), encoding="utf-8") as f:
                fields = f.read().split()
            total += int(fields[2]) * 512
        except (OSError, IndexError, ValueError):
            continue
    return total


def plan_reads(files: list[str], max_bytes: int) -> tuple[list[str], int, int]:
    """Choose what to read under a byte cap.

    Drops missing paths, then skips any file that would push the total past
    max_bytes. Skips whole files rather than truncating, so everything read
    is fully warm.
    """
    keep: list[str] = []
    total = 0
    skipped = 0
    for path in files:
        try:
            size = os.path.getsize(path)
        except OSError:
            continue
        if total + size > max_bytes:
            skipped += size
            continue
        keep.append(path)
        total += size
    return keep, total, skipped


def _read_all(paths: list[str]) -> int:
    """Read every path fully. Returns bytes actually read.

    open/readv errors are skipped, not counted -- a file that fails to open
    contributes 0, not its planned size.
    """
    buf = bytearray(READ_CHUNK)
    total = 0
    for path in paths:
        try:
            fd = os.open(path, os.O_RDONLY)
        except OSError:
            continue
        try:
            while True:
                n = os.readv(fd, [buf])
                if not n:
                    break
                total += n
        except OSError:
            pass
        finally:
            os.close(fd)
    return total


def warm(files: list[str], workers: int) -> int:
    """Read every file across N forked readers. Returns bytes actually read.

    Forks, not threads, so the GIL is not in the way. Each child reports its
    real byte count back over a pipe rather than the parent re-deriving a
    planned total from os.path.getsize(): that used to make `warm()` return
    what was PLANNED, not what was READ, so a file that failed to open (or a
    whole shard whose reads all failed) was silently absorbed into a total
    that always looked healthy.
    """
    if not files:
        return 0
    n = max(1, min(workers, len(files)))
    shards = [files[i::n] for i in range(n)]
    pids: list[int] = []
    read_ends: list[int] = []
    for shard in shards:
        r, w = os.pipe()
        pid = os.fork()
        if pid == 0:
            os.close(r)
            try:
                got = _read_all(shard)
                os.write(w, got.to_bytes(8, "big"))
            finally:
                os._exit(0)
        os.close(w)
        pids.append(pid)
        read_ends.append(r)

    total = 0
    for pid, r in zip(pids, read_ends):
        data = b""
        while len(data) < 8:
            chunk = os.read(r, 8 - len(data))
            if not chunk:
                break
            data += chunk
        os.close(r)
        os.waitpid(pid, 0)
        if len(data) == 8:
            total += int.from_bytes(data, "big")
    return total
