"""Tests for residency measurement and parallel warming."""

from __future__ import annotations

import os
import tempfile
import unittest

import warm


def _mkfile(size: int) -> str:
    d = tempfile.mkdtemp()
    p = os.path.join(d, "f.bin")
    with open(p, "wb") as f:
        f.write(os.urandom(4096) * (size // 4096))
        f.flush()
        os.fsync(f.fileno())
    return p


class TestResident(unittest.TestCase):
    def test_evict_then_read_changes_residency(self) -> None:
        """Control test for mincore.

        MUST use a file no other process has mapped. FADV_DONTNEED on a mapped
        file is a no-op, which once made a working helper look broken.
        """
        p = _mkfile(8 << 20)
        fd = os.open(p, os.O_RDONLY)
        os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
        os.close(fd)
        after_evict, size = warm.resident(p)
        self.assertEqual(size, 8 << 20)
        # FADV_DONTNEED is a silent no-op on tmpfs. tempfile lands on /tmp,
        # which can be tmpfs inside a build sandbox even where it is a real
        # fs on the host. Skip rather than fail when eviction did not stick.
        if after_evict >= size // 2:
            raise unittest.SkipTest(
                "backing fs does not honour FADV_DONTNEED (tmpfs?)"
            )
        self.assertLess(after_evict, size // 2)

        fd = os.open(p, os.O_RDONLY)
        while os.read(fd, 1 << 20):
            pass
        os.close(fd)
        after_read, _ = warm.resident(p)
        self.assertGreaterEqual(after_read, size - 4096)

    def test_empty_file(self) -> None:
        d = tempfile.mkdtemp()
        p = os.path.join(d, "empty")
        open(p, "w", encoding="utf-8").close()
        self.assertEqual(warm.resident(p), (0, 0))

    def test_missing_file(self) -> None:
        self.assertEqual(warm.resident("/nonexistent"), (0, 0))


class TestPlanReads(unittest.TestCase):
    def test_under_cap_takes_everything(self) -> None:
        a, b = _mkfile(4096), _mkfile(4096)
        files, total, skipped = warm.plan_reads([a, b], 1 << 30)
        self.assertEqual(sorted(files), sorted([a, b]))
        self.assertEqual(total, 8192)
        self.assertEqual(skipped, 0)

    def test_cap_skips_the_overflow(self) -> None:
        a, b = _mkfile(8192), _mkfile(8192)
        files, total, skipped = warm.plan_reads([a, b], 8192)
        self.assertEqual(files, [a])
        self.assertEqual(total, 8192)
        self.assertEqual(skipped, 8192)

    def test_missing_files_are_dropped(self) -> None:
        a = _mkfile(4096)
        files, total, skipped = warm.plan_reads([a, "/nonexistent"], 1 << 30)
        self.assertEqual(files, [a])
        self.assertEqual(total, 4096)
        self.assertEqual(skipped, 0)


class TestWarm(unittest.TestCase):
    def test_warm_populates_page_cache(self) -> None:
        files = [_mkfile(4 << 20) for _ in range(4)]
        for p in files:
            fd = os.open(p, os.O_RDONLY)
            os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
            os.close(fd)
        got = warm.warm(files, workers=2)
        self.assertEqual(got, 4 * (4 << 20))
        for p in files:
            res, size = warm.resident(p)
            self.assertGreaterEqual(res, size - 4096)

    def test_warm_of_nothing_is_zero(self) -> None:
        self.assertEqual(warm.warm([], workers=4), 0)


if __name__ == "__main__":
    unittest.main()
