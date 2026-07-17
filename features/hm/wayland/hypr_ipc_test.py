#!/usr/bin/env python3
"""Unit tests for the pure helper in hypr_ipc.py (stdlib only)."""
import unittest

import hypr_ipc


class ParseEvent(unittest.TestCase):
    def test_name_and_data(self):
        self.assertEqual(hypr_ipc.parse_event("monitorremoved>>DP-2"),
                         ("monitorremoved", "DP-2"))

    def test_data_may_contain_separator(self):
        self.assertEqual(hypr_ipc.parse_event("movewindowv2>>0x1,2,special:magic"),
                         ("movewindowv2", "0x1,2,special:magic"))

    def test_no_separator_gives_empty_data(self):
        self.assertEqual(hypr_ipc.parse_event("configreloaded"), ("configreloaded", ""))

    def test_empty_line(self):
        self.assertEqual(hypr_ipc.parse_event(""), ("", ""))


if __name__ == "__main__":
    unittest.main()
