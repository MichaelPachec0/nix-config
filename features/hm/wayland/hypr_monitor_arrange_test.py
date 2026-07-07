#!/usr/bin/env python3
"""Unit tests for the pure helpers in hypr_monitor_arrange.py (stdlib only)."""
import unittest

import hypr_monitor_arrange as hma


class ParseEvent(unittest.TestCase):
    def test_name_and_data(self):
        self.assertEqual(hma.parse_event("monitorremoved>>DP-2"), ("monitorremoved", "DP-2"))

    def test_data_may_contain_separator(self):
        self.assertEqual(hma.parse_event("monitoraddedv2>>1,DP-2,Acme >> X"),
                         ("monitoraddedv2", "1,DP-2,Acme >> X"))

    def test_no_separator_gives_empty_data(self):
        self.assertEqual(hma.parse_event("configreloaded"), ("configreloaded", ""))

    def test_empty_line(self):
        self.assertEqual(hma.parse_event(""), ("", ""))


class IsTriggerEvent(unittest.TestCase):
    def test_monitorremoved_triggers(self):
        self.assertTrue(hma.is_trigger_event("monitorremoved"))

    def test_prefix_variant_triggers(self):
        self.assertTrue(hma.is_trigger_event("monitorremovedv2"))

    def test_monitoradded_does_not_trigger(self):
        self.assertFalse(hma.is_trigger_event("monitoraddedv2"))

    def test_unrelated_event_does_not_trigger(self):
        self.assertFalse(hma.is_trigger_event("openwindow"))


class FakeClock:
    """A hand-cranked monotonic clock for deterministic Debouncer tests."""

    def __init__(self, t=0.0):
        self.t = t

    def __call__(self):
        return self.t

    def advance(self, dt):
        self.t += dt


class DebouncerTest(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.d = hma.Debouncer(0.6, self.clock)

    def test_idle_is_not_pending(self):
        self.assertFalse(self.d.pending())
        self.assertIsNone(self.d.time_until())
        self.assertFalse(self.d.due())

    def test_arm_then_wait_then_due(self):
        self.d.arm()
        self.assertTrue(self.d.pending())
        self.assertAlmostEqual(self.d.time_until(), 0.6)
        self.assertFalse(self.d.due())
        self.clock.advance(0.5)
        self.assertFalse(self.d.due())
        self.assertAlmostEqual(self.d.time_until(), 0.1)
        self.clock.advance(0.1)
        self.assertTrue(self.d.due())

    def test_time_until_never_negative(self):
        self.d.arm()
        self.clock.advance(5.0)
        self.assertEqual(self.d.time_until(), 0.0)

    def test_rearm_extends_the_window(self):
        self.d.arm()          # fire_at = 0.6
        self.clock.advance(0.5)
        self.d.arm()          # fire_at = 1.1
        self.assertFalse(self.d.due())
        self.clock.advance(0.5)  # t = 1.0, still < 1.1
        self.assertFalse(self.d.due())
        self.clock.advance(0.1)  # t = 1.1
        self.assertTrue(self.d.due())

    def test_clear_disarms(self):
        self.d.arm()
        self.d.clear()
        self.assertFalse(self.d.pending())
        self.assertIsNone(self.d.time_until())
        self.assertFalse(self.d.due())


if __name__ == "__main__":
    unittest.main()
