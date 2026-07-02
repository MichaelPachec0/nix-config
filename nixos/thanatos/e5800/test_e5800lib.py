import unittest
import e5800lib as L


class TestAuthGen(unittest.TestCase):
    def test_login_hash(self):
        # sha256("root:CIPHER:NONCE")
        import hashlib
        want = hashlib.sha256(b"root:CIPHER:NONCE").hexdigest()
        self.assertEqual(L.login_hash("root", "CIPHER", "NONCE"), want)

    def test_gen_from_network_type(self):
        self.assertEqual(L.gen_from_network_type("NR5G-NSA"), "5G")
        self.assertEqual(L.gen_from_network_type("NR5G-SA"), "5G")
        self.assertEqual(L.gen_from_network_type("LTE"), "4G")
        self.assertEqual(L.gen_from_network_type("LTE-A"), "4G")
        self.assertEqual(L.gen_from_network_type("WCDMA"), "3G")
        self.assertEqual(L.gen_from_network_type(""), "?")
        self.assertEqual(L.gen_from_network_type(None), "?")


class TestUsage(unittest.TestCase):
    # 2026-07-02 12:00 UTC = 1782043200; 2026-07-01 00:00 UTC = 1782000000... use datetime.
    def _ts(self, y, mo, d, h=0):
        import datetime
        return int(datetime.datetime(y, mo, d, h, tzinfo=datetime.timezone.utc).timestamp())

    def test_cycle_anchor_after_reset_day(self):
        now = self._ts(2026, 7, 15)
        self.assertEqual(L.cycle_anchor(now, 1), self._ts(2026, 7, 1))

    def test_cycle_anchor_before_reset_day_rolls_to_prev_month(self):
        now = self._ts(2026, 7, 15)
        self.assertEqual(L.cycle_anchor(now, 20), self._ts(2026, 6, 20))

    def test_first_sample_seeds_state(self):
        now = self._ts(2026, 7, 5)
        st = L.usage_step({}, 1000, 500, now, 1)
        self.assertEqual(st["cycle_rx"], 1000)
        self.assertEqual(st["cycle_tx"], 500)
        self.assertEqual(st["last_rx"], 1000)
        self.assertEqual(st["cycle_start"], self._ts(2026, 7, 1))

    def test_incremental_delta(self):
        now = self._ts(2026, 7, 5)
        st = L.usage_step({}, 1000, 500, now, 1)
        st = L.usage_step(st, 1500, 800, now, 1)
        self.assertEqual(st["cycle_rx"], 1500)  # 1000 + 500 delta
        self.assertEqual(st["cycle_tx"], 800)

    def test_counter_reset_adds_full_current(self):
        now = self._ts(2026, 7, 5)
        st = L.usage_step({}, 1000, 500, now, 1)     # cycle_rx=1000
        st = L.usage_step(st, 200, 100, now, 1)      # cur<last => bounce; add 200/100
        self.assertEqual(st["cycle_rx"], 1200)
        self.assertEqual(st["cycle_tx"], 600)

    def test_cycle_rollover_zeroes(self):
        st = L.usage_step({}, 1000, 500, self._ts(2026, 6, 15), 1)
        st = L.usage_step(st, 1200, 600, self._ts(2026, 7, 2), 1)  # crossed Jul 1
        self.assertEqual(st["cycle_rx"], 1200)  # reset to 0 then +1200 (bounce vs last across reset)
        self.assertEqual(st["cycle_start"], self._ts(2026, 7, 1))


class TestBuildStatus(unittest.TestCase):
    def test_unreachable_is_minimal(self):
        s = L.build_status({"ts": 100, "reachable": False})
        self.assertEqual(s, {"schema": 1, "ts": 100, "reachable": False})

    def test_full_shape(self):
        parts = {
            "ts": 1782980135, "reachable": True, "carrier": "T-Mobile",
            "info": {"model": "e5800", "firmware_version": "4.8.5"},
            "get_status": {
                "system": {"cpu": {"temperature": 40}, "load_average": [2.25, 1.6, 1.5],
                           "memory_total": 1675968512, "memory_free": 847491072,
                           "memory_buff_cache": 338063360, "flash_total": 7818182656,
                           "flash_free": 2852933632, "uptime": 13551,
                           "mcu": {"charge_percent": 72, "charging_status": 0,
                                   "fastcharge": False, "temperature": 31.2}},
                "network": [{"interface": "tethering", "online": False, "up": False},
                            {"interface": "modem_cpu", "online": True, "up": True}],
                "client": [{"wireless_total": 3, "cable_total": 0, "usbeth_total": 0}],
                "wifi": [{"band": "2G", "ssid": "x", "up": True, "guest": False},
                         {"band": "6G", "ssid": "y", "up": False, "guest": False}],
            },
            "get_speed": {"speed_rx": 30, "speed_tx": 929},
            "get_list": {"clients": [{"name": "laptop", "ip": "192.168.8.232",
                                      "online": True, "rx": 1100, "tx": 300}]},
            "vpn": {"status_list": [{"name": "mullvad", "type": "wireguard", "enabled": False}]},
            "signals": [{"slot": 1, "strength": 4, "network_type": "NR5G-NSA",
                         "rsrp": -73, "rsrq": -10, "sinr": 30}],
            "usage": {"cycle_rx": 5000000000, "cycle_tx": 400000000,
                      "cycle_start": 1782000000},
            "recovery": None,
        }
        s = L.build_status(parts)
        self.assertTrue(s["reachable"])
        self.assertEqual(s["uplink"]["interface"], "modem_cpu")
        self.assertTrue(s["uplink"]["online"])
        self.assertEqual(s["battery"]["percent"], 72)
        self.assertFalse(s["battery"]["charging"])
        self.assertEqual(s["cellular"]["gen"], "5G")
        self.assertEqual(s["cellular"]["rsrp"], -73)
        self.assertEqual(s["cellular"]["strength"], 4)
        self.assertTrue(s["cellular"]["supported"])
        self.assertEqual(s["clients"]["wireless"], 3)
        self.assertEqual(s["clients"]["list"][0]["name"], "laptop")
        self.assertEqual(s["wifi"][0]["band"], "2G")
        self.assertFalse(s["vpn"]["active"])
        self.assertEqual(s["data"]["cycle_rx"], 5000000000)
        self.assertEqual(s["device"]["carrier"], "T-Mobile")
        self.assertEqual(s["recovery"]["active"], False)

    def test_recovery_marker_sets_active(self):
        parts = {"ts": 1, "reachable": True, "recovery": {"action": "airplane", "started": 99}}
        s = L.build_status(parts)
        self.assertTrue(s["recovery"]["active"])
        self.assertEqual(s["recovery"]["action"], "airplane")
        self.assertEqual(s["recovery"]["started"], 99)

    def test_no_signal_marks_unsupported(self):
        parts = {"ts": 1, "reachable": True, "signals": []}
        s = L.build_status(parts)
        self.assertFalse(s["cellular"]["supported"])


if __name__ == "__main__":
    unittest.main()
