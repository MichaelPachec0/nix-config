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


class TestQeng(unittest.TestCase):
    # Real AT+QENG="servingcell" capture: 5G NSA, LTE B2 anchor + NR n41, idle.
    SAMPLE = ('\r\n+QENG: "servingcell","NOCONN"\r\n'
              '+QENG: "LTE","FDD",310,260,1762809,322,675,2,4,4,3C6E,'
              '-88,-18,-51,16,13,-110,-\r\n'
              '+QENG: "NR5G-NSA",310,260,704,-81,22,-10,501390,41,12,1\r\n\r\nOK\r\n')

    def test_parses_nsa_two_bands(self):
        r = L.parse_qeng(self.SAMPLE)
        self.assertEqual(r["state"], "NOCONN")
        self.assertEqual(r["mode"], "NSA")
        self.assertEqual(r["count"], 2)
        self.assertEqual(r["bands"], ["B2", "n41"])

    def test_cells_detail(self):
        cells = L.parse_qeng(self.SAMPLE)["cells"]
        self.assertEqual(cells[0], {"rat": "LTE", "band": 2, "label": "B2"})
        self.assertEqual(cells[1]["rat"], "NR5G-NSA")
        self.assertEqual(cells[1]["band"], 41)
        self.assertEqual(cells[1]["label"], "n41")

    def test_lte_only(self):
        data = ('\r\n+QENG: "servingcell","CONNECT"\r\n'
                '+QENG: "LTE","FDD",310,260,1762809,322,675,66,4,4,3C6E,'
                '-88,-18,-51,16,13,-110,-\r\n\r\nOK\r\n')
        r = L.parse_qeng(data)
        self.assertEqual(r["mode"], "LTE")
        self.assertEqual(r["bands"], ["B66"])
        self.assertEqual(r["count"], 1)
        self.assertEqual(r["state"], "CONNECT")

    def test_empty_and_no_service_return_none(self):
        self.assertIsNone(L.parse_qeng(None))
        self.assertIsNone(L.parse_qeng(""))
        self.assertIsNone(L.parse_qeng("\r\nOK\r\n"))
        self.assertIsNone(L.parse_qeng("\r\n+QNWINFO: No Service\r\n\r\nOK\r\n"))


class TestQcainfo(unittest.TestCase):
    # Real AT+QCAINFO capture: 3-carrier EN-DC. PCC LTE B66 + NR n41 (short-form
    # PSCell, active) + NR n71 (scell_state=1, configured but deactivated).
    NSA = ('+QCAINFO: "PCC",66786,100,"LTE BAND 66",1,322,-92,-10,-59,6\r\n'
           '+QCAINFO: "SCC",521310,11,"NR5G BAND 41",704\r\n'
           '+QCAINFO: "SCC",126530,3,"NR5G BAND 71",1,71,0,-,-\r\n\r\nOK\r\n')

    def test_nsa_three_carriers(self):
        r = L.parse_qcainfo(self.NSA)
        self.assertEqual(r["count"], 3)
        self.assertEqual(r["active_count"], 2)
        self.assertEqual(r["mode"], "NSA")
        self.assertEqual(r["bands"], ["B66", "n41", "n71"])

    def test_nsa_carrier_states(self):
        cs = L.parse_qcainfo(self.NSA)["carriers"]
        self.assertEqual(cs[0], {"role": "PCC", "rat": "LTE", "band": 66,
                                 "label": "B66", "state": None, "active": True})
        self.assertEqual(cs[1]["label"], "n41")
        self.assertTrue(cs[1]["active"])           # short-form PSCell
        self.assertEqual(cs[2]["label"], "n71")
        self.assertEqual(cs[2]["state"], 1)
        self.assertFalse(cs[2]["active"])          # configured, deactivated

    def test_lte_scc_activated(self):
        # Manual doc example: LTE PCC B1 + LTE SCC B3 (scell_state=2, activated).
        data = ('+QCAINFO: "PCC",300,100,"LTE BAND 1",1,23,-66,-12,-34,30\r\n'
                '+QCAINFO: "SCC",1575,100,"LTE BAND 3",2,43,-64,-7,-24,30,0,-,-'
                '\r\n\r\nOK\r\n')
        r = L.parse_qcainfo(data)
        self.assertEqual(r["mode"], "LTE")
        self.assertEqual(r["count"], 2)
        self.assertEqual(r["active_count"], 2)
        self.assertEqual(r["bands"], ["B1", "B3"])

    def test_sa_mode(self):
        # NR PCC (SA short form) + NR SCC activated.
        data = ('+QCAINFO: "PCC",647328,12,"NR5G BAND 78",500\r\n'
                '+QCAINFO: "SCC",633984,3,"NR5G BAND 78",2,501,1,3,647328'
                '\r\n\r\nOK\r\n')
        r = L.parse_qcainfo(data)
        self.assertEqual(r["mode"], "SA")
        self.assertEqual(r["count"], 2)
        self.assertEqual(r["bands"], ["n78", "n78"])

    def test_deconfigured_scc_excluded_but_present(self):
        # scell_state=0 -> deconfigured: not counted, still listed (dim in UI).
        data = ('+QCAINFO: "PCC",66786,100,"LTE BAND 66",1,322,-92,-10,-59,6\r\n'
                '+QCAINFO: "SCC",126530,3,"NR5G BAND 71",0,71,0,-,-\r\n\r\nOK\r\n')
        r = L.parse_qcainfo(data)
        self.assertEqual(r["count"], 1)              # only PCC configured
        self.assertEqual(r["bands"], ["B66"])
        self.assertEqual(len(r["carriers"]), 2)      # n71 still listed
        self.assertEqual(r["carriers"][1]["state"], 0)
        self.assertFalse(r["carriers"][1]["active"])

    def test_no_pcc_and_empty_return_none(self):
        self.assertIsNone(L.parse_qcainfo(None))
        self.assertIsNone(L.parse_qcainfo(""))
        self.assertIsNone(L.parse_qcainfo("\r\nOK\r\n"))
        self.assertIsNone(L.parse_qcainfo(
            '+QCAINFO: "SCC",126530,3,"NR5G BAND 71",1,71,0,-,-\r\n'))


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

    def test_qcainfo_wired_into_cellular_ca(self):
        parts = {"ts": 1, "reachable": True,
                 "qcainfo": '+QCAINFO: "PCC",66786,100,"LTE BAND 66",1,322,'
                            '-92,-10,-59,6\r\n'
                            '+QCAINFO: "SCC",521310,11,"NR5G BAND 41",704'
                            '\r\n\r\nOK\r\n'}
        ca = L.build_status(parts)["cellular"]["ca"]
        self.assertEqual(ca["count"], 2)
        self.assertEqual(ca["bands"], ["B66", "n41"])
        self.assertEqual(ca["active_count"], 2)

    def test_qeng_wired_into_cellular_serving(self):
        parts = {"ts": 1, "reachable": True,
                 "qeng": '\r\n+QENG: "servingcell","NOCONN"\r\n'
                         '+QENG: "NR5G-NSA",310,260,704,-81,22,-10,501390,41,'
                         '12,1\r\n\r\nOK\r\n'}
        serving = L.build_status(parts)["cellular"]["serving"]
        self.assertEqual(serving["bands"], ["n41"])
        self.assertEqual(serving["mode"], "NSA")

    def test_no_at_payloads_leave_ca_and_serving_none(self):
        cell = L.build_status({"ts": 1, "reachable": True})["cellular"]
        self.assertIsNone(cell["ca"])
        self.assertIsNone(cell["serving"])

    def test_auth_error_defaults_false(self):
        s = L.build_status({"ts": 1, "reachable": True})
        self.assertFalse(s["auth_error"])

    def test_auth_error_propagates(self):
        s = L.build_status({"ts": 1, "reachable": True, "auth_error": True})
        self.assertTrue(s["auth_error"])

    def test_unreachable_has_no_auth_error_key(self):
        s = L.build_status({"ts": 1, "reachable": False, "auth_error": True})
        self.assertNotIn("auth_error", s)  # unreachable == off the router, not an auth problem


class TestRecover(unittest.TestCase):
    def test_command_map(self):
        import e5800_recover as R
        self.assertIn("redial", R.RECOVER_CMDS)
        self.assertIn("airplane", R.RECOVER_CMDS)
        self.assertIn("reboot", R.RECOVER_CMDS)
        # redial bounces the named interface (no bus needed)
        self.assertTrue(any("network.interface.modem_cpu" in c
                            and "down" in c for c in R.RECOVER_CMDS["redial"]))
        self.assertTrue(any("network.interface.modem_cpu" in c
                            and "up" in c for c in R.RECOVER_CMDS["redial"]))
        # airplane toggles on then off
        self.assertTrue(any("set_airplane_mode" in c and "true" in c
                            for c in R.RECOVER_CMDS["airplane"]))
        self.assertTrue(any("set_airplane_mode" in c and "false" in c
                            for c in R.RECOVER_CMDS["airplane"]))
        # reboot is the AT+CFUN=1,1 radio reset
        self.assertTrue(any("CFUN=1,1" in c for c in R.RECOVER_CMDS["reboot"]))


if __name__ == "__main__":
    unittest.main()
