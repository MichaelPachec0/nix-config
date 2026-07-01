#!/usr/bin/env python3
"""Unit tests for the pure helpers in hypr_window_keeper.py (stdlib only)."""
import unittest

import hypr_window_keeper as hwk

# 1920x1080 @ scale 1 with a 40px top bar (reserved = [left, top, right, bottom]).
MON = {"id": 0, "x": 0, "y": 0, "width": 1920, "height": 1080, "scale": 1,
       "reserved": [0, 40, 0, 0]}
# Same logical layout via a HiDPI panel: 3840x2160 @ scale 2 -> 1920x1080 logical.
MON_HIDPI = {"id": 1, "x": 0, "y": 0, "width": 3840, "height": 2160, "scale": 2,
             "reserved": [0, 40, 0, 0]}


class UsableArea(unittest.TestCase):
    def test_reserved_top_bar(self):
        self.assertEqual(hwk.usable_area(MON), (0, 40, 1920, 1040))

    def test_scale_is_divided_out(self):
        self.assertEqual(hwk.usable_area(MON_HIDPI), (0, 40, 1920, 1040))

    def test_monitor_offset_and_all_edges(self):
        mon = {"x": 100, "y": 200, "width": 1000, "height": 1000, "scale": 1,
               "reserved": [10, 20, 30, 40]}
        # x=100+10, y=200+20, w=1000-10-30, h=1000-20-40
        self.assertEqual(hwk.usable_area(mon), (110, 220, 960, 940))


class ComputeTarget(unittest.TestCase):
    def test_center_matches_live_windscribe(self):
        # 350x600 centered on MON is exactly where Hyprland put it (785, 260).
        self.assertEqual(hwk.compute_target({"kind": "center"}, [350, 600], MON), (785, 260))

    def test_center_respects_scale(self):
        self.assertEqual(hwk.compute_target({"kind": "center"}, [350, 600], MON_HIDPI), (785, 260))

    def test_fixed_is_monitor_relative(self):
        mon = {**MON, "x": 500, "y": 300}
        self.assertEqual(hwk.compute_target({"kind": "fixed", "x": 100, "y": 60}, [10, 10], mon),
                         (600, 360))

    def test_anchor_corners(self):
        pos = lambda a: {"kind": "anchor", "anchor": a, "margin": 10}
        size = [200, 100]  # usable = (0, 40, 1920, 1040)
        self.assertEqual(hwk.compute_target(pos("top-left"), size, MON), (10, 50))
        self.assertEqual(hwk.compute_target(pos("top-right"), size, MON), (1710, 50))
        self.assertEqual(hwk.compute_target(pos("bottom-left"), size, MON), (10, 970))
        self.assertEqual(hwk.compute_target(pos("bottom-right"), size, MON), (1710, 970))

    def test_anchor_edges_center_the_free_axis(self):
        pos = lambda a: {"kind": "anchor", "anchor": a, "margin": 10}
        size = [200, 100]
        self.assertEqual(hwk.compute_target(pos("top"), size, MON), (860, 50))
        self.assertEqual(hwk.compute_target(pos("bottom"), size, MON), (860, 970))
        self.assertEqual(hwk.compute_target(pos("left"), size, MON), (10, 510))
        self.assertEqual(hwk.compute_target(pos("right"), size, MON), (1710, 510))

    def test_anchor_center_equals_center(self):
        size = [200, 100]
        self.assertEqual(hwk.compute_target({"kind": "anchor", "anchor": "center", "margin": 10}, size, MON),
                         hwk.compute_target({"kind": "center"}, size, MON))


class Matches(unittest.TestCase):
    WIN = {"class": "", "title": "Windscribe", "initialClass": "", "initialTitle": "Windscribe"}

    def test_title_regex_matches_empty_class_window(self):
        self.assertTrue(hwk.matches({"title": "^Windscribe$"}, self.WIN))

    def test_class_match_fails_when_class_empty(self):
        self.assertFalse(hwk.matches({"class": "^Windscribe$"}, self.WIN))

    def test_search_is_substring(self):
        self.assertTrue(hwk.matches({"title": "scribe"}, self.WIN))

    def test_all_fields_must_match(self):
        self.assertTrue(hwk.matches({"title": "Windscribe", "initialTitle": "Windscribe"}, self.WIN))
        self.assertFalse(hwk.matches({"title": "Windscribe", "class": "x"}, self.WIN))

    def test_missing_field_is_empty_string(self):
        self.assertFalse(hwk.matches({"class": "."}, {"title": "x"}))


class NormalizePosition(unittest.TestCase):
    def test_center_string(self):
        self.assertEqual(hwk.normalize_position("center"), {"kind": "center"})

    def test_fixed(self):
        self.assertEqual(hwk.normalize_position({"x": 100, "y": 60}),
                         {"kind": "fixed", "x": 100, "y": 60})

    def test_anchor_with_margin(self):
        self.assertEqual(hwk.normalize_position({"anchor": "top-right", "margin": 12}),
                         {"kind": "anchor", "anchor": "top-right", "margin": 12})

    def test_anchor_defaults_margin_zero(self):
        self.assertEqual(hwk.normalize_position({"anchor": "center"}),
                         {"kind": "anchor", "anchor": "center", "margin": 0})

    def test_invalid_string_raises(self):
        with self.assertRaises(ValueError):
            hwk.normalize_position("nope")

    def test_empty_dict_raises(self):
        with self.assertRaises(ValueError):
            hwk.normalize_position({})


class ParseRules(unittest.TestCase):
    def test_normalizes_each_rule(self):
        cfg = {"rules": [
            {"match": {"title": "^Windscribe$"}, "position": "center"},
            {"match": {"class": "^Foo$"}, "position": {"anchor": "top-right", "margin": 8}},
        ]}
        rules = hwk.parse_rules(cfg)
        self.assertEqual(len(rules), 2)
        self.assertEqual(rules[0], {"match": {"title": "^Windscribe$"}, "pos": {"kind": "center"}})
        self.assertEqual(rules[1]["pos"], {"kind": "anchor", "anchor": "top-right", "margin": 8})

    def test_empty(self):
        self.assertEqual(hwk.parse_rules({}), [])


if __name__ == "__main__":
    unittest.main()
