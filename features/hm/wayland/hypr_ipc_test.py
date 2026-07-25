#!/usr/bin/env python3
"""Unit tests for the pure helpers in hypr_ipc.py (stdlib only)."""
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


class RequestJson(unittest.TestCase):
    """request_json's parse/default logic, with the socket I/O (request) stubbed."""

    def setUp(self):
        self._orig = hypr_ipc.request
        self.sent = []
        self._reply = ""

        def fake_request(sig, cmd):
            self.sent.append((sig, cmd))
            return self._reply

        hypr_ipc.request = fake_request

    def tearDown(self):
        hypr_ipc.request = self._orig

    def test_parses_json_and_adds_j_prefix(self):
        self._reply = '[{"id": 0}]'
        self.assertEqual(hypr_ipc.request_json("SIG", "clients"), [{"id": 0}])
        self.assertEqual(self.sent, [("SIG", "j/clients")])

    def test_empty_reply_is_none(self):
        self._reply = ""
        self.assertIsNone(hypr_ipc.request_json("SIG", "clients"))

    def test_malformed_reply_is_none(self):
        self._reply = "not json"
        self.assertIsNone(hypr_ipc.request_json("SIG", "monitors"))


if __name__ == "__main__":
    unittest.main()
