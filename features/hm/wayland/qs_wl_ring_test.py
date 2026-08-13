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


if __name__ == "__main__":
    unittest.main()
