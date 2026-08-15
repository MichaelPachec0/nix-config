#!/usr/bin/env python3
"""Unit tests for the pure helpers in fix_stuck_keys.py (stdlib only)."""
import unittest

import fix_stuck_keys as fsk

# The exact set the cat produced: KEY_3, KEY_Q, KEY_GRAVE, KEY_KP0, KEY_VOLUMEUP.
CAT_KEYS = [4, 16, 41, 82, 115]


class FakeClock:
    """A hand-cranked monotonic clock for deterministic HeldTracker tests."""

    def __init__(self, t=0.0):
        self.t = t

    def __call__(self):
        return self.t

    def advance(self, dt):
        self.t += dt


class IsKeyboardCode(unittest.TestCase):
    def test_letter_is_a_keyboard_code(self):
        self.assertTrue(fsk.is_keyboard_code(16))  # KEY_Q

    def test_highest_keyboard_code_included(self):
        self.assertTrue(fsk.is_keyboard_code(fsk.BTN_MISC - 1))

    def test_mouse_button_excluded(self):
        self.assertFalse(fsk.is_keyboard_code(0x110))  # BTN_LEFT

    def test_btn_misc_itself_excluded(self):
        self.assertFalse(fsk.is_keyboard_code(fsk.BTN_MISC))

    def test_code_zero_excluded(self):
        # KEY_RESERVED is never a real press; releasing it would be noise.
        self.assertFalse(fsk.is_keyboard_code(0))


class HeldTracker(unittest.TestCase):
    def test_first_sighting_stamps_now(self):
        clock = FakeClock(100.0)
        tracker = fsk.HeldTracker(clock)
        self.assertEqual(tracker.update([16]), {16: 100.0})

    def test_continuous_hold_keeps_original_stamp(self):
        clock = FakeClock(100.0)
        tracker = fsk.HeldTracker(clock)
        tracker.update([16])
        clock.advance(30.0)
        self.assertEqual(tracker.update([16]), {16: 100.0})

    def test_release_then_press_restarts_the_timer(self):
        # This is what makes ordinary typing invisible to the rules: no key
        # survives a full press/release cycle with its timer intact.
        clock = FakeClock(100.0)
        tracker = fsk.HeldTracker(clock)
        tracker.update([16])
        clock.advance(5.0)
        tracker.update([])
        clock.advance(5.0)
        self.assertEqual(tracker.update([16]), {16: 110.0})

    def test_keys_added_later_carry_their_own_stamp(self):
        clock = FakeClock(0.0)
        tracker = fsk.HeldTracker(clock)
        tracker.update([4])
        clock.advance(3.0)
        self.assertEqual(tracker.update([4, 16]), {4: 0.0, 16: 3.0})

    def test_buttons_are_never_tracked(self):
        tracker = fsk.HeldTracker(FakeClock(0.0))
        self.assertEqual(tracker.update([0x110, 16]), {16: 0.0})

    def test_forget_restarts_tracking(self):
        clock = FakeClock(0.0)
        tracker = fsk.HeldTracker(clock)
        tracker.update([16])
        tracker.forget([16])
        clock.advance(50.0)
        self.assertEqual(tracker.update([16]), {16: 50.0})


class DecideReleases(unittest.TestCase):
    def setUp(self):
        self.cfg = fsk.Config(
            cat_keys=3, cat_hold_s=10.0, lone_hold_s=120.0, gpu_busy_pct=45
        )

    def held(self, codes, stamp=0.0):
        return {code: stamp for code in codes}

    def test_nothing_held_releases_nothing(self):
        self.assertEqual(fsk.decide_releases({}, 999.0, 0, self.cfg), [])

    def test_cat_signature_releases_everything(self):
        held = self.held(CAT_KEYS)
        self.assertEqual(fsk.decide_releases(held, 10.0, 0, self.cfg), sorted(CAT_KEYS))

    def test_cat_signature_needs_the_full_hold(self):
        held = self.held(CAT_KEYS)
        self.assertEqual(fsk.decide_releases(held, 9.9, 0, self.cfg), [])

    def test_modifiers_do_not_count_toward_the_cat_signature(self):
        # Ctrl+Shift+Alt held together is a normal chord, not a ghosted matrix.
        held = self.held([29, 42, 56])
        self.assertEqual(fsk.decide_releases(held, 60.0, 0, self.cfg), [])

    def test_stuck_modifier_is_released_once_the_cat_rule_fires(self):
        # A stuck modifier is the most disruptive case, so it goes too.
        held = self.held([29, 4, 16, 41])
        self.assertEqual(fsk.decide_releases(held, 10.0, 0, self.cfg), [4, 16, 29, 41])

    def test_two_keys_are_below_the_cat_threshold(self):
        held = self.held([4, 16])
        self.assertEqual(fsk.decide_releases(held, 60.0, 0, self.cfg), [])

    def test_lone_straggler_released_after_the_long_timer(self):
        held = self.held([82])
        self.assertEqual(fsk.decide_releases(held, 120.0, 0, self.cfg), [82])

    def test_lone_straggler_spared_before_the_long_timer(self):
        held = self.held([82])
        self.assertEqual(fsk.decide_releases(held, 119.9, 0, self.cfg), [])

    def test_only_aged_keys_are_released_by_the_straggler_rule(self):
        held = {82: 0.0, 16: 119.0}
        self.assertEqual(fsk.decide_releases(held, 120.0, 0, self.cfg), [82])

    def test_partially_aged_set_does_not_trip_the_cat_rule(self):
        # Two keys aged past the hold, a third only just added: not yet a
        # ten-second-stable set, so nothing fires.
        held = {4: 0.0, 16: 0.0, 41: 9.0}
        self.assertEqual(fsk.decide_releases(held, 10.0, 0, self.cfg), [])

    def test_busy_gpu_blocks_the_cat_rule(self):
        held = self.held(CAT_KEYS)
        self.assertEqual(fsk.decide_releases(held, 600.0, 90, self.cfg), [])

    def test_busy_gpu_blocks_the_straggler_rule(self):
        held = self.held([82])
        self.assertEqual(fsk.decide_releases(held, 600.0, 90, self.cfg), [])

    def test_gpu_exactly_at_threshold_blocks(self):
        held = self.held(CAT_KEYS)
        self.assertEqual(fsk.decide_releases(held, 600.0, 45, self.cfg), [])

    def test_gpu_just_below_threshold_allows(self):
        held = self.held(CAT_KEYS)
        self.assertEqual(
            fsk.decide_releases(held, 600.0, 44, self.cfg), sorted(CAT_KEYS)
        )

    def test_unknown_gpu_is_treated_as_idle(self):
        # An unreadable sysfs node must not silently disable the watchdog.
        held = self.held(CAT_KEYS)
        self.assertEqual(
            fsk.decide_releases(held, 600.0, None, self.cfg), sorted(CAT_KEYS)
        )


class ParseArgs(unittest.TestCase):
    def test_default_mode_is_one_shot(self):
        args = fsk.parse_args([])
        self.assertFalse(args.daemon)
        self.assertFalse(args.check)

    def test_daemon_and_check_are_mutually_exclusive(self):
        with self.assertRaises(SystemExit):
            fsk.parse_args(["--daemon", "--check"])

    def test_thresholds_are_overridable(self):
        args = fsk.parse_args(["--daemon", "--gpu-busy-percent=70", "--cat-keys=4"])
        self.assertEqual(args.gpu_busy_percent, 70)
        self.assertEqual(args.cat_keys, 4)


class EventEncoding(unittest.TestCase):
    def test_input_event_is_24_bytes(self):
        # 64-bit struct input_event: two 8-byte timeval longs, u16, u16, s32.
        self.assertEqual(fsk.EVENT_SIZE, 24)

    def test_key_bitmap_covers_key_max(self):
        self.assertEqual(fsk.KEY_BITMAP_BYTES * 8, 0x2FF + 1)


if __name__ == "__main__":
    unittest.main()
