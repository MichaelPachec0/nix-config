#!/usr/bin/env python3
"""Unit tests for the pure classify() in hypr_scratchpad_guard.py (stdlib only)."""
import unittest

import hypr_scratchpad_guard as g


class Classify(unittest.TestCase):
    def test_unfloat_evicts(self):
        self.assertEqual(g.classify("changefloatingmode", "593cb426c700,0"),
                         ("evict", "593cb426c700"))

    def test_float_on_is_ignored(self):
        self.assertEqual(g.classify("changefloatingmode", "593cb426c700,1"),
                         (None, None))

    def test_move_into_special_floatfixes(self):
        self.assertEqual(g.classify("movewindowv2", "593cb426c700,-98,special:magic"),
                         ("float-fix", "593cb426c700"))

    def test_move_into_normal_ws_is_ignored(self):
        self.assertEqual(g.classify("movewindowv2", "593cb426c700,1,1"),
                         (None, None))

    def test_openwindow_is_ignored(self):
        # openwindow is deliberately not watched (float-rule race).
        self.assertEqual(g.classify("openwindow", "593cb426c700,special:magic,kitty,x"),
                         (None, None))

    def test_unrelated_event_is_ignored(self):
        self.assertEqual(g.classify("activewindowv2", "593cb426c700"), (None, None))

    def test_malformed_changefloatingmode_is_ignored(self):
        self.assertEqual(g.classify("changefloatingmode", "593cb426c700"), (None, None))


if __name__ == "__main__":
    unittest.main()
