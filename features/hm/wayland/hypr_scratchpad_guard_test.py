#!/usr/bin/env python3
"""Unit tests for the pure classify() in hypr_scratchpad_guard.py (stdlib only)."""
import unittest

import hypr_scratchpad_guard as g


class Classify(unittest.TestCase):
    def test_move_into_special_floatfixes(self):
        self.assertEqual(g.classify("movewindowv2", "593cb426c700,-98,special:magic"),
                         ("float-fix", "593cb426c700"))

    def test_move_into_normal_ws_is_ignored(self):
        self.assertEqual(g.classify("movewindowv2", "593cb426c700,1,1"),
                         (None, None))

    def test_changefloatingmode_is_ignored(self):
        # Hyprland emits no socket2 event on a float change, so eviction is
        # keybind-driven (Super+Shift+f -> toggle-float), NOT guard-driven. The
        # guard must not act on changefloatingmode even if one somehow arrived.
        self.assertEqual(g.classify("changefloatingmode", "593cb426c700,0"), (None, None))
        self.assertEqual(g.classify("changefloatingmode", "593cb426c700,1"), (None, None))

    def test_openwindow_is_ignored(self):
        # openwindow is deliberately not watched (float-rule race).
        self.assertEqual(g.classify("openwindow", "593cb426c700,special:magic,kitty,x"),
                         (None, None))

    def test_unrelated_event_is_ignored(self):
        self.assertEqual(g.classify("activewindowv2", "593cb426c700"), (None, None))


class RunLine(unittest.TestCase):
    """run_line parses 'cmd [arg]' and forwards to scratchpad_cycle.run_command
    (stubbed, so no Hyprland I/O runs)."""

    def setUp(self):
        import scratchpad_cycle
        self._sc = scratchpad_cycle
        self._orig = scratchpad_cycle.run_command
        self.calls = []
        scratchpad_cycle.run_command = lambda cmd, arg=None: self.calls.append((cmd, arg))

    def tearDown(self):
        self._sc.run_command = self._orig

    def test_cmd_only(self):
        g.run_line("cycle")
        self.assertEqual(self.calls, [("cycle", None)])

    def test_cmd_with_arg(self):
        g.run_line("float-fix 0xabc")
        self.assertEqual(self.calls, [("float-fix", "0xabc")])

    def test_blank_is_noop(self):
        g.run_line("")
        g.run_line("   ")
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
