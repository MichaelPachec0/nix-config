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


def _read_all(paths: list[str]) -> None:
    buf = bytearray(READ_CHUNK)
    for path in paths:
        try:
            fd = os.open(path, os.O_RDONLY)
        except OSError:
            continue
        try:
            while os.readv(fd, [buf]):
                pass
        except OSError:
            pass
        finally:
            os.close(fd)


def warm(files: list[str], workers: int) -> int:
    """Read every file across N forked readers. Returns bytes read.

    Forks, not threads, so the GIL is not in the way.
    """
    if not files:
        return 0
    total = 0
    for path in files:
        try:
            total += os.path.getsize(path)
        except OSError:
            pass
    n = max(1, min(workers, len(files)))
    shards = [files[i::n] for i in range(n)]
    pids: list[int] = []
    for shard in shards:
        pid = os.fork()
        if pid == 0:
            try:
                _read_all(shard)
            finally:
                os._exit(0)
        pids.append(pid)
    for pid in pids:
        os.waitpid(pid, 0)
    return total
