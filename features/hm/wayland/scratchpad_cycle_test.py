#!/usr/bin/env python3
"""Unit tests for the pure rotation logic in scratchpad_cycle.py."""
import unittest

import scratchpad_cycle as sc


class Plan(unittest.TestCase):
    def test_empty_pool_no_shown(self):
        self.assertEqual(sc.plan([], None), (None, None, None))

    def test_show_first_when_nothing_shown(self):
        self.assertEqual(sc.plan(["b", "a"], None), (None, "a", "a"))  # sorted -> "a" first

    def test_rotate_to_next(self):
        # "a" is out, "b"/"c" parked -> hide a, show b
        self.assertEqual(sc.plan(["b", "c"], "a"), ("a", "b", "b"))

    def test_rotate_middle(self):
        self.assertEqual(sc.plan(["a", "c"], "b"), ("b", "c", "c"))

    def test_last_member_cycles_to_empty(self):
        # "c" is out (last of a,b,c) -> hide c, show nothing (empty step)
        self.assertEqual(sc.plan(["a", "b"], "c"), ("c", None, None))

    def test_single_member_shown_toggles_off(self):
        self.assertEqual(sc.plan([], "a"), ("a", None, None))

    def test_single_member_hidden_shows_it(self):
        self.assertEqual(sc.plan(["a"], None), (None, "a", "a"))

    def test_shown_also_in_hidden_is_deduped(self):
        # defensive: if state and clients disagree, shown is unioned once
        self.assertEqual(sc.plan(["a", "b"], "a"), ("a", "b", "b"))

    def test_full_rotation_includes_empty(self):
        # Two members a, b. Walk: empty -> a -> b -> empty -> a ...
        self.assertEqual(sc.plan(["a", "b"], None), (None, "a", "a"))  # -> a
        self.assertEqual(sc.plan(["b"], "a"), ("a", "b", "b"))         # a->b
        self.assertEqual(sc.plan(["a"], "b"), ("b", None, None))       # b->empty
        self.assertEqual(sc.plan(["a", "b"], None), (None, "a", "a"))  # empty->a


class UpdateMembers(unittest.TestCase):
    def test_learns_parked_windows(self):
        # nothing known yet; a and b are parked -> both become members
        self.assertEqual(sc.update_members([], ["a", "b"], None, ["a", "b", "c"]),
                         ["a", "b"])

    def test_keeps_shown_out_member(self):
        # a is pulled out (shown), b parked -> both are members
        self.assertEqual(sc.update_members(["a"], ["b"], "a", ["a", "b"]),
                         ["a", "b"])

    def test_prunes_closed_windows(self):
        # z was a member but is no longer open -> dropped
        self.assertEqual(sc.update_members(["a", "z"], ["b"], None, ["a", "b"]),
                         ["a", "b"])

    def test_unions_prior_members(self):
        # a previously recorded, out and untracked this run, still a member
        self.assertEqual(sc.update_members(["a"], [], None, ["a", "b"]), ["a"])


class ReleasedByMove(unittest.TestCase):
    def test_still_on_show_ws_not_released(self):
        # shown on ws 1, still on ws 1 -> normal rotation, not extracted
        self.assertFalse(sc.released_by_move("1", 1, "1"))

    def test_moved_to_other_ws_released(self):
        # shown on ws 1, user moved it to ws 4 -> extracted
        self.assertTrue(sc.released_by_move("4", 4, "1"))

    def test_back_in_special_not_released(self):
        # already back in the pad -> the stale check owns this, not release
        self.assertFalse(sc.released_by_move(sc.SPECIAL_WS, -98, "1"))

    def test_no_recorded_show_ws_not_released(self):
        # old-format state (no show_ws) -> can't tell, don't release
        self.assertFalse(sc.released_by_move("4", 4, None))

    def test_no_current_ws_not_released(self):
        self.assertFalse(sc.released_by_move(None, None, "1"))

    def test_id_str_int_equivalence(self):
        # show_ws persisted as str "2", current id is int 2 -> same ws
        self.assertFalse(sc.released_by_move("2", 2, "2"))


class NormalizeAddr(unittest.TestCase):
    def test_adds_0x_prefix(self):
        self.assertEqual(sc.normalize_addr("593cb426c700"), "0x593cb426c700")

    def test_keeps_existing_prefix(self):
        self.assertEqual(sc.normalize_addr("0x593cb426c700"), "0x593cb426c700")

    def test_lowercases(self):
        self.assertEqual(sc.normalize_addr("0x593CB426C700"), "0x593cb426c700")

    def test_lowercases_unprefixed(self):
        self.assertEqual(sc.normalize_addr("593CB426C700"), "0x593cb426c700")

    def test_none_is_none(self):
        self.assertIsNone(sc.normalize_addr(None))

    def test_empty_is_none(self):
        self.assertIsNone(sc.normalize_addr(""))

    def test_whitespace_is_none(self):
        self.assertIsNone(sc.normalize_addr("   "))


class Forget(unittest.TestCase):
    def test_drops_member_and_clears_shown(self):
        self.assertEqual(sc.forget("0xa", ["0xa", "0xb"], "0xa"), (["0xb"], True))

    def test_drops_member_keeps_other_shown(self):
        self.assertEqual(sc.forget("0xa", ["0xa", "0xb"], "0xb"), (["0xb"], False))

    def test_not_a_member_is_noop(self):
        self.assertEqual(sc.forget("0xz", ["0xa", "0xb"], "0xa"), (["0xa", "0xb"], False))

    def test_no_shown(self):
        self.assertEqual(sc.forget("0xa", ["0xa", "0xb"], None), (["0xb"], False))


if __name__ == "__main__":
    unittest.main()
