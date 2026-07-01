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


if __name__ == "__main__":
    unittest.main()
