#!/usr/bin/env python3
"""Unit tests for the pure helpers in qs_wl_ring.py (stdlib only)."""
import os
import tempfile
import unittest

import qs_wl_ring as ring


class RingLines(unittest.TestCase):
    def test_keeps_the_tail_not_the_head(self):
        # The whole point: the interesting window is the LAST second before the
        # client died, so an over-long stream must drop its oldest lines.
        self.assertEqual(ring.ring_lines(["a", "b", "c"], 2), ["b", "c"])

    def test_shorter_than_limit_is_untouched(self):
        self.assertEqual(ring.ring_lines(["a"], 5), ["a"])

    def test_empty_stream(self):
        self.assertEqual(ring.ring_lines([], 5), [])


class Dump(unittest.TestCase):
    def test_writes_lines_verbatim(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "out.log")
            ring.dump(["one\n", "two\n"], path)
            with open(path) as handle:
                self.assertEqual(handle.read(), "one\ntwo\n")

    def test_replaces_previous_content_whole(self):
        # Snapshots overwrite rather than append; a shorter second dump must not
        # leave a tail of the longer first one behind.
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "out.log")
            ring.dump(["long line one\n", "long line two\n"], path)
            ring.dump(["short\n"], path)
            with open(path) as handle:
                self.assertEqual(handle.read(), "short\n")

    def test_leaves_no_tmp_file_behind(self):
        # The tmp+rename is what stops an interrupted snapshot truncating the
        # last good one; a leftover .tmp would mean the rename never happened.
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "out.log")
            ring.dump(["x\n"], path)
            self.assertEqual(sorted(os.listdir(tmp)), ["out.log"])


class RunPath(unittest.TestCase):
    def test_stamp_and_pid_go_before_the_extension(self):
        self.assertEqual(
            ring.run_path("/s/wl-tail.log", "20260818T092639Z", 1042677),
            "/s/wl-tail-20260818T092639Z-1042677.log",
        )

    def test_extensionless_base_gets_one(self):
        self.assertEqual(
            ring.run_path("/s/wl-tail", "20260818T092639Z", 7),
            "/s/wl-tail-20260818T092639Z-7.log",
        )

    def test_lexical_order_is_chronological_order(self):
        # prunable() sorts by name and calls the result oldest-first, which is
        # only true while the stamp is fixed-width and leads. A pid that sorts
        # the other way must not be able to reorder two different seconds.
        early = ring.run_path("/s/t.log", "20260818T092639Z", 999999)
        late = ring.run_path("/s/t.log", "20260818T092640Z", 1)
        self.assertLess(early, late)

    def test_glob_matches_run_files_but_not_the_base(self):
        import fnmatch

        base = "/s/wl-tail.log"
        pattern = ring.run_glob(base)
        self.assertTrue(
            fnmatch.fnmatch(ring.run_path(base, "20260818T092639Z", 7), pattern)
        )
        # The base path is the "current run" symlink; pruning must never eat it.
        self.assertFalse(fnmatch.fnmatch(base, pattern))


class Prunable(unittest.TestCase):
    def test_drops_the_oldest_beyond_the_limit(self):
        paths = ["t-1.log", "t-2.log", "t-3.log"]
        self.assertEqual(ring.prunable(paths, 2), ["t-1.log"])

    def test_under_the_limit_keeps_everything(self):
        self.assertEqual(ring.prunable(["t-1.log"], 5), [])

    def test_unsorted_input_is_ordered_before_slicing(self):
        # glob() returns directory order, not sorted order.
        paths = ["t-3.log", "t-1.log", "t-2.log"]
        self.assertEqual(ring.prunable(paths, 1), ["t-1.log", "t-2.log"])

    def test_zero_keep_deletes_nothing(self):
        # Deleting every run including the one in progress is the single
        # unrecoverable outcome, so a nonsense QS_WL_KEEP disables pruning.
        self.assertEqual(ring.prunable(["t-1.log", "t-2.log"], 0), [])
        self.assertEqual(ring.prunable(["t-1.log", "t-2.log"], -1), [])


class LinkCurrent(unittest.TestCase):
    def test_points_at_the_run_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = os.path.join(tmp, "wl-tail.log")
            target = os.path.join(tmp, "wl-tail-A-1.log")
            ring.dump(["x\n"], target)
            ring.link_current(base, target)
            with open(base) as handle:
                self.assertEqual(handle.read(), "x\n")

    def test_is_relative_so_the_directory_can_move(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = os.path.join(tmp, "wl-tail.log")
            target = os.path.join(tmp, "wl-tail-A-1.log")
            ring.dump([], target)
            ring.link_current(base, target)
            self.assertEqual(os.readlink(base), "wl-tail-A-1.log")

    def test_replaces_an_existing_link(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = os.path.join(tmp, "wl-tail.log")
            first = os.path.join(tmp, "wl-tail-A-1.log")
            second = os.path.join(tmp, "wl-tail-B-2.log")
            ring.dump(["first\n"], first)
            ring.dump(["second\n"], second)
            ring.link_current(base, first)
            ring.link_current(base, second)
            with open(base) as handle:
                self.assertEqual(handle.read(), "second\n")

    def test_leaves_no_tmp_link_behind(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = os.path.join(tmp, "wl-tail.log")
            target = os.path.join(tmp, "wl-tail-A-1.log")
            ring.dump([], target)
            ring.link_current(base, target)
            self.assertEqual(
                sorted(os.listdir(tmp)), ["wl-tail-A-1.log", "wl-tail.log"]
            )


if __name__ == "__main__":
    unittest.main()
