import json
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
        # reboot is a full Linux reboot of the router, not a modem reset
        self.assertEqual(R.RECOVER_CMDS["reboot"], ["ubus call system reboot"])

    def test_no_recovery_action_opens_the_at_channel(self):
        """The rule the whole migration exists to enforce.

        modem.CPU.AT is /dev/smd9, owned by cellular_manager's AT process.
        Writing to it from here shares the channel with GL's own poller, which
        answers with crossed responses. `reboot` violated this until 2026-08-01
        by sending AT+CFUN=1,1; this fails if any action reintroduces it.
        """
        import e5800_recover as R
        for action, cmds in R.RECOVER_CMDS.items():
            for c in cmds:
                self.assertNotIn("modem.CPU.AT", c, action)
                self.assertNotIn("AT+", c, action)


if __name__ == "__main__":
    unittest.main()


class TestOperator(unittest.TestCase):
    """The operator name is only knowable from QENG's PLMN.

    AT+COPS? on this firmware answers a bare "+COPS: 5" with no <format>/<oper>
    fields, and AT+QSPN answers a bare OK -- verified against the live modem on
    2026-07-31. QENG, already fetched every cycle for band info, reports the
    registered PLMN, so no extra AT round-trip is needed.
    """

    # Injected rather than read from the vendored table, so these assert the
    # RULES and cannot break when upstream data changes.
    TABLE = {
        "310-260": [{"cc": "US", "brand": "T-Mobile", "operator": "T-Mobile US",
                     "status": "Operational"}],
        "310-410": [{"cc": "US", "brand": "AT&T", "operator": "AT&T Mobility",
                     "status": "Operational"}],
    }

    def test_known_plmn_resolves_to_a_name(self):
        self.assertEqual(L.operator_from_plmn("310", "260", ["US"], self.TABLE), "T-Mobile")
        self.assertEqual(L.operator_from_plmn("310", "410", ["US"], self.TABLE), "AT&T")

    def test_unknown_plmn_falls_back_to_the_number(self):
        # Not None and not a guess: "which network" is still answered by the
        # number, and MVNOs share a PLMN with their host so a guess would lie.
        self.assertEqual(L.operator_from_plmn("000", "000", ["US"], self.TABLE), "000-000")

    def test_missing_plmn_is_none(self):
        self.assertIsNone(L.operator_from_plmn(None, None))
        self.assertIsNone(L.operator_from_plmn("310", None))
        self.assertIsNone(L.operator_from_plmn(None, "260"))
        self.assertIsNone(L.operator_from_plmn("", ""))

    def test_mnc_digits_are_not_normalised(self):
        # MNC 26 and MNC 260 are different networks; padding or stripping a
        # digit would resolve one to the other's name.
        self.assertEqual(L.fmt_plmn("310", "26"), "310-26")
        self.assertEqual(L.fmt_plmn("310", "260"), "310-260")
        self.assertNotEqual(L.operator_from_plmn("310", "26", ["US"], self.TABLE),
                            L.operator_from_plmn("310", "260", ["US"], self.TABLE))

    def test_qeng_nsa_capture_carries_the_operator(self):
        r = L.parse_qeng(TestQeng.SAMPLE, ["US"])
        self.assertEqual(r["plmn"], "310-260")
        self.assertEqual(r["operator"], "T-Mobile")

    def test_qeng_lte_only_carries_the_operator(self):
        data = ('\r\n+QENG: "servingcell","CONNECT"\r\n'
                '+QENG: "LTE","FDD",310,410,1762809,322,675,66,4,4,3C6E,'
                '-88,-18,-51,16,13,-110,-\r\n\r\nOK\r\n')
        self.assertEqual(L.parse_qeng(data, ["US"])["operator"], "AT&T")

    def test_nr5g_only_reads_the_plmn_one_token_earlier(self):
        # NR5G lines have no duplex field, so the PLMN sits at a different
        # index than on LTE lines. Reading the LTE offset here would yield the
        # cell id as the MNC and silently produce a wrong network.
        data = ('\r\n+QENG: "servingcell","NOCONN"\r\n'
                '+QENG: "NR5G-NSA",310,260,704,-81,22,-10,501390,41,12,1'
                '\r\n\r\nOK\r\n')
        r = L.parse_qeng(data, ["US"])
        self.assertEqual(r["plmn"], "310-260")
        self.assertEqual(r["operator"], "T-Mobile")

    def test_no_serving_cell_yields_no_operator(self):
        # parse_qeng returns None outright when nothing is camped, so the
        # status builder must render nothing rather than "Unknown".
        self.assertIsNone(L.parse_qeng('\r\n+QENG: "servingcell","NOCONN"\r\n\r\nOK\r\n'))

    def test_build_status_lifts_operator_onto_cellular(self):
        st = L.build_status({"reachable": True, "country_hint": ["US"],
                             "signals": [{"network_type": "NR5G-NSA", "rsrp": -88}],
                             "qeng": TestQeng.SAMPLE})
        self.assertEqual(st["cellular"]["operator"], "T-Mobile")
        self.assertEqual(st["cellular"]["plmn"], "310-260")

    def test_build_status_without_qeng_has_no_operator(self):
        st = L.build_status({"reachable": True, "country_hint": ["US"],
                             "signals": [{"network_type": "NR5G-NSA", "rsrp": -88}]})
        self.assertIsNone(st["cellular"]["operator"])
        self.assertIsNone(st["cellular"]["plmn"])


class TestDebugAtInfo(unittest.TestCase):
    """cellular.network debug_at_info is the arbitrated AT path.

    Real capture from the RG650V-NA on 2026-08-01, trimmed to the commands the
    poller consumes. The full response carries 32.
    """
    QENG = ("\r\n+QENG: \"servingcell\",\"NOCONN\"\r\n"
            "+QENG: \"LTE\",\"FDD\",310,260,1762803,322,66786,66,5,5,"
            "3C6E,-99,-11,-66,11,12,50,-\r\n"
            "+QENG: \"NR5G-NSA\",310,260,704,-88,23,-10,501390,41,12,1"
            "\r\n\r\nOK\r\n")
    SAMPLE = json.dumps({
        "msgs": [
            {"cmd": "ATI",
             "result": "\r\nQuectel\r\nRG650V-NA\r\n\r\nOK\r\n"},
            {"cmd": "AT+CEREG?", "result": "\r\n+CEREG: 0,1\r\n\r\nOK\r\n"},
            {"cmd": "AT+COPS?",
             "result": "\r\n+COPS: 0,0,\"Mint\",13\r\n\r\nOK\r\n"},
            {"cmd": "AT+QCAINFO",
             "result": "\r\n+QCAINFO: \"PCC\",66786,100,\"LTE BAND 66\","
                       "1,322,-99,-11,-66,3\r\n"
                       "+QCAINFO: \"SCC\",501390,12,\"NR5G BAND 41\",704\r\n"
                       "\r\nOK\r\n"},
            {"cmd": "AT+QENG=\"servingcell\"", "result": QENG},
        ],
        "ret": 0,
        "resp": "Success",
    })

    def test_splits_by_command(self):
        got = L.parse_debug_at(self.SAMPLE)
        self.assertIn("AT+CEREG?", got)
        self.assertIn("AT+QCAINFO", got)
        self.assertIn('AT+QENG="servingcell"', got)

    def test_results_feed_the_existing_parsers_unchanged(self):
        # The whole point of the migration: same raw AT text arrives by a
        # different route, so no parser needed rewriting.
        got = L.parse_debug_at(self.SAMPLE)
        self.assertEqual(L.parse_cereg(got["AT+CEREG?"]), "home")
        serving = L.parse_qeng(got['AT+QENG="servingcell"'], ["US"])
        self.assertEqual(serving["bands"], ["B66", "n41"])
        self.assertEqual(serving["plmn"], "310-260")
        self.assertEqual(serving["operator"], "T-Mobile")
        self.assertEqual(L.parse_qcainfo(got["AT+QCAINFO"])["count"], 2)

    def test_failed_call_yields_nothing_so_caches_survive(self):
        # A non-zero ret must latch NOTHING. Returning partial data here would
        # let a failed call overwrite good cached readings.
        self.assertEqual(
            L.parse_debug_at(json.dumps({"resp": "Parameter missing", "ret": 15})),
            {})

    def test_nonzero_ret_is_rejected_even_when_msgs_are_present(self):
        # The `ret` check must carry its own weight. A rejected call that still
        # returns a msgs list is the case that matters: the missing-msgs shape
        # above is also caught by the type check, so it cannot prove this.
        got = L.parse_debug_at(json.dumps({
            "ret": 15,
            "resp": "Parameter missing",
            "msgs": [{"cmd": "AT+CEREG?", "result": "\r\nERROR\r\n"}],
        }))
        self.assertEqual(got, {})

    def test_garbage_and_empty_are_survivable(self):
        for bad in ("", None, "not json", "[]", json.dumps({"ret": 0})):
            self.assertEqual(L.parse_debug_at(bad), {})

    def test_entries_without_a_result_are_dropped(self):
        got = L.parse_debug_at(json.dumps({"ret": 0, "msgs": [
            {"cmd": "AT+CEREG?", "result": ""},
            {"cmd": "AT+QCAINFO"},
            {"result": "orphan"},
            "not a dict",
        ]}))
        self.assertEqual(got, {})

    def test_first_non_empty_result_wins(self):
        got = L.parse_debug_at(json.dumps({"ret": 0, "msgs": [
            {"cmd": "AT+CEREG?", "result": "\r\n+CEREG: 0,5\r\n\r\nOK\r\n"},
            {"cmd": "AT+CEREG?", "result": "\r\nERROR\r\n"},
        ]}))
        self.assertEqual(L.parse_cereg(got["AT+CEREG?"]), "roaming")

    def test_cops_is_not_a_network_name_source(self):
        # +COPS returns the SPN ("Mint"), not the registered network, so the
        # network half of operator_label must keep coming from the QENG PLMN.
        # Guarding this because COPS looks like the obvious shortcut.
        got = L.parse_debug_at(self.SAMPLE)
        self.assertIn('"Mint"', got["AT+COPS?"])
        serving = L.parse_qeng(got['AT+QENG="servingcell"'], ["US"])
        self.assertEqual(
            L.operator_label("Mint", serving["operator"],
                             L.parse_cereg(got["AT+CEREG?"])),
            "Mint (T-Mobile)")


class TestBattery(unittest.TestCase):
    """mcu status + mcu get_warning. Real captures."""
    STATUS = json.dumps({
        "abnormal": False, "abnormal_type": 0, "charge_cnt": 28,
        "charge_percent": 80, "charging_status": 1, "fastcharge": False,
        "temperature": "39.0",
    })
    WARNING = json.dumps({
        "capacity": {"enable": False, "interval": 5, "value": 10,
                     "warned": False},
        "temp_high": {"enable": False, "interval": 5, "value": 50,
                      "warned": False},
        "temp_low": {"enable": False, "interval": 5, "value": -10,
                     "warned": False},
    })

    def test_status_fields(self):
        r = L.parse_mcu_status(self.STATUS)
        self.assertEqual(r["percent"], 80)
        self.assertEqual(r["cycles"], 28)
        self.assertTrue(r["charging"])
        self.assertFalse(r["abnormal"])

    def test_temperature_string_becomes_a_number(self):
        # The firmware sends "39.0" as a string in the same object where
        # charge_percent is an int. Leaving it a string breaks any comparison
        # against the numeric warning threshold.
        r = L.parse_mcu_status(self.STATUS)
        self.assertEqual(r["temp"], 39)
        self.assertIsInstance(r["temp"], (int, float))
        self.assertLess(r["temp"], 50)

    def test_thresholds_keep_their_enable_flag_separate(self):
        # Both ship disabled. The value must survive that, or the popup
        # inherits the router's silence and stays green at 51C.
        w = L.parse_mcu_warning(self.WARNING)
        self.assertEqual(w["temp_high"], 50)
        self.assertFalse(w["temp_high_enabled"])
        self.assertEqual(w["capacity"], 10)
        self.assertFalse(w["capacity_enabled"])

    def test_garbage_and_empty_are_survivable(self):
        for bad in ("", None, "not json", "[]"):
            self.assertIsNone(L.parse_mcu_status(bad))
            self.assertIsNone(L.parse_mcu_warning(bad))

    def test_build_status_prefers_ubus_and_gains_wear(self):
        st = L.build_status({
            "reachable": True,
            "mcu": L.parse_mcu_status(self.STATUS),
            "mcu_warning": L.parse_mcu_warning(self.WARNING),
        })
        b = st["battery"]
        self.assertEqual(b["percent"], 80)
        self.assertEqual(b["cycles"], 28)
        self.assertEqual(b["temp"], 39)
        self.assertEqual(b["warn_temp"], 50)

    def test_web_values_still_populate_before_the_first_ubus_read(self):
        st = L.build_status({
            "reachable": True,
            "get_status": {"system": {"mcu": {"charge_percent": 71,
                                              "charging_status": 0,
                                              "temperature": "41.5"}}},
        })
        b = st["battery"]
        self.assertEqual(b["percent"], 71)
        self.assertEqual(b["temp"], 41.5)
        self.assertIsNone(b["cycles"])

    def test_a_real_zero_is_not_treated_as_missing(self):
        # Battery percent, temperature and cycle count are all legitimately
        # zero. Chaining the two sources with `or` would fall through to the
        # web value exactly when the ubus reading said 0 -- reporting a flat
        # battery as whatever the other source last said.
        st = L.build_status({
            "reachable": True,
            "mcu": L.parse_mcu_status(json.dumps({
                "charge_percent": 0, "temperature": "0", "charge_cnt": 0})),
            "get_status": {"system": {"mcu": {"charge_percent": 80,
                                              "temperature": "39.0"}}},
        })
        self.assertEqual(st["battery"]["percent"], 0)
        self.assertEqual(st["battery"]["temp"], 0)
        self.assertEqual(st["battery"]["cycles"], 0)


class TestIfaceStatus(unittest.TestCase):
    """network.interface.modem_cpu status -- the uplink's own facts.

    Real capture, trimmed. The route list matters: the DNS servers each get a
    /32 route on this interface, so the default route has to be selected rather
    than assumed to be first.
    """
    SAMPLE = json.dumps({
        "up": True, "uptime": 12663, "l3_device": "rmnet_data0",
        "proto": "rmnet",
        "ipv4-address": [{"address": "48.18.141.141", "mask": 30}],
        "dns-server": ["10.177.0.34", "10.177.0.210"],
        "route": [
            {"target": "10.177.0.34", "mask": 32, "nexthop": "0.0.0.0"},
            {"target": "10.177.0.210", "mask": 32, "nexthop": "0.0.0.0"},
            {"target": "0.0.0.0", "mask": 0, "nexthop": "48.18.141.142",
             "mtu": 1500},
        ],
    })

    def test_reads_the_uplink_facts(self):
        r = L.parse_iface_status(self.SAMPLE)
        self.assertEqual(r["uptime"], 12663)
        self.assertEqual(r["device"], "rmnet_data0")
        self.assertEqual(r["ip"], "48.18.141.141")
        self.assertEqual(r["mask"], 30)
        self.assertEqual(r["dns"], ["10.177.0.34", "10.177.0.210"])
        self.assertTrue(r["up"])

    def test_gateway_is_the_default_route_not_the_first_one(self):
        # The /32 DNS routes are listed first and their nexthop is 0.0.0.0.
        # Taking route[0] would report the gateway as 0.0.0.0.
        self.assertEqual(L.parse_iface_status(self.SAMPLE)["gateway"],
                         "48.18.141.142")

    def test_partial_interface_still_yields_what_it_knows(self):
        # Dialling, or up with no lease yet: uptime is real, addressing is not.
        r = L.parse_iface_status(json.dumps({"up": False, "uptime": 4}))
        self.assertEqual(r["uptime"], 4)
        self.assertIsNone(r["ip"])
        self.assertIsNone(r["gateway"])
        self.assertEqual(r["dns"], [])

    def test_garbage_and_empty_are_survivable(self):
        for bad in ("", None, "not json", "[]"):
            self.assertIsNone(L.parse_iface_status(bad))

    def test_build_status_keeps_the_two_uptimes_separate(self):
        # system.uptime is the router's; uplink.uptime is the modem's. Conflating
        # them would hide exactly the redial the pair exists to expose.
        st = L.build_status({
            "reachable": True,
            "get_status": {"system": {"uptime": 276164}},
            "iface": L.parse_iface_status(self.SAMPLE),
        })
        self.assertEqual(st["system"]["uptime"], 276164)
        self.assertEqual(st["uplink"]["uptime"], 12663)

    def test_absent_iface_leaves_uplink_uptime_none_not_zero(self):
        # Zero would render as a link that just dialled this instant.
        st = L.build_status({"reachable": True})
        self.assertIsNone(st["uplink"]["uptime"])


class TestSimCarrier(unittest.TestCase):
    """cellular.sim status replaces AT+QSPN as the source of the SIM's brand."""
    SAMPLE = json.dumps({"sims": [
        {"slot": "1", "carrier": "Mint", "iccid": "8901240367198032843F",
         "apn": "fast.t-mobile.com", "status": 6, "strength": 4},
        {"slot": "2", "carrier": "", "iccid": "", "status": 0},
    ]})

    def test_reads_the_populated_slot(self):
        self.assertEqual(L.parse_sim_status(self.SAMPLE)["carrier"], "Mint")

    def test_empty_slots_are_skipped_not_returned_blank(self):
        # Slot ordering is not guaranteed; an empty slot listed first must not
        # shadow the live one.
        payload = json.dumps({"sims": [{"slot": "2", "carrier": ""},
                                       {"slot": "1", "carrier": "Mint"}]})
        self.assertEqual(L.parse_sim_status(payload)["carrier"], "Mint")

    def test_apn_comes_from_the_same_row(self):
        # No extra call: the bearer is in the payload already fetched for the
        # brand.
        r = L.parse_sim_status(self.SAMPLE)
        self.assertEqual(r["apn"], "fast.t-mobile.com")
        self.assertEqual(r["slot"], "1")

    def test_blank_apn_is_none_not_empty_string(self):
        # An empty string renders as a stray label with nothing after it.
        r = L.parse_sim_status(json.dumps({"sims": [
            {"slot": "1", "carrier": "Mint", "apn": ""}]}))
        self.assertIsNone(r["apn"])

    def test_build_status_carries_the_apn(self):
        st = L.build_status({"reachable": True, "apn": "fast.t-mobile.com"})
        self.assertEqual(st["cellular"]["apn"], "fast.t-mobile.com")

    def test_no_sim_yields_none_not_a_blank_name(self):
        self.assertIsNone(L.parse_sim_status(json.dumps({"sims": [
            {"slot": "1", "carrier": ""}]})))

    def test_garbage_and_empty_are_survivable(self):
        for bad in ("", None, "not json", "[]", json.dumps({}),
                    json.dumps({"sims": ["nope"]})):
            self.assertIsNone(L.parse_sim_status(bad))

    def test_build_status_prefers_the_direct_name_over_qspn(self):
        st = L.build_status({
            "reachable": True, "country_hint": ["US"],
            "sim_operator": "Mint",
            "signals": [{"network_type": "NR5G-NSA"}],
            "qeng": TestDebugAtInfo.QENG,
        })
        self.assertEqual(st["cellular"]["sim_operator"], "Mint")
        self.assertEqual(st["cellular"]["operator_label"], "Mint (T-Mobile)")

    def test_qspn_still_works_when_no_direct_name_is_supplied(self):
        # The AT path is retired, not deleted -- a SIM that does carry an SPN
        # record must keep resolving, and existing fixtures must keep passing.
        st = L.build_status({
            "reachable": True, "country_hint": ["US"],
            "qspn": "\r\n+QSPN: \"Ultra\",\"Ultra\",\"\",0,\"310260\"\r\n\r\nOK\r\n",
            "signals": [{"network_type": "NR5G-NSA"}],
            "qeng": TestDebugAtInfo.QENG,
        })
        self.assertEqual(st["cellular"]["operator_label"], "Ultra (T-Mobile)")


class TestSimOperator(unittest.TestCase):
    """An MVNO's brand lives on the SIM, not in the network registration.

    A Mint SIM reports "Mint" via AT+QSPN while riding T-Mobile's network,
    which QENG reports as PLMN 310-260. The two are different facts and the
    display shows both.
    """

    # Real AT+QSPN capture from the RG650V, 2026-08-01. NOTE the empty third
    # field: this SIM populates FNN and SNN but not SPN, so a parser that read
    # only SPN would find nothing on a SIM that plainly has a name.
    SAMPLE = '\r\n+QSPN: "Mint","Mint","",0,"310260"\r\n\r\nOK\r\n'

    def test_parses_the_sim_name(self):
        self.assertEqual(L.parse_qspn(self.SAMPLE), "Mint")

    def test_bare_ok_is_none(self):
        # Observed on this modem 2026-07-31: a SIM with no SPN record answers
        # a bare OK. Must be None so the caller falls back to the network name
        # rather than rendering a blank.
        self.assertIsNone(L.parse_qspn('\r\nOK\r\n'))
        self.assertIsNone(L.parse_qspn(''))
        self.assertIsNone(L.parse_qspn(None))

    def test_empty_leading_fields_fall_through(self):
        # FNN empty but SNN populated: take the first non-empty of the three
        # rather than returning "" and losing the name.
        self.assertEqual(L.parse_qspn('\r\n+QSPN: "","TMO","",0,"310260"\r\n\r\nOK\r\n'), "TMO")

    def test_all_name_fields_empty_is_none(self):
        self.assertIsNone(L.parse_qspn('\r\n+QSPN: "","","",0,"310260"\r\n\r\nOK\r\n'))

    def test_label_shows_both_when_they_differ(self):
        self.assertEqual(L.operator_label("Mint", "T-Mobile"), "Mint (T-Mobile)")

    def test_label_collapses_when_they_match(self):
        # A direct subscriber must never see "T-Mobile (T-Mobile)".
        self.assertEqual(L.operator_label("T-Mobile", "T-Mobile"), "T-Mobile")
        self.assertEqual(L.operator_label("T-MOBILE", "T-Mobile"), "T-MOBILE")

    def test_label_falls_back_to_whichever_half_exists(self):
        self.assertEqual(L.operator_label(None, "T-Mobile"), "T-Mobile")
        self.assertEqual(L.operator_label("Mint", None), "Mint")
        self.assertEqual(L.operator_label("", "T-Mobile"), "T-Mobile")
        self.assertIsNone(L.operator_label(None, None))
        self.assertIsNone(L.operator_label("", ""))

    def test_label_handles_roaming(self):
        # The same shape carries a genuinely useful fact when roaming.
        self.assertEqual(L.operator_label("Mint", "AT&T"), "Mint (AT&T)")

    def test_build_status_composes_the_label(self):
        st = L.build_status({"reachable": True, "country_hint": ["US"],
                             "signals": [{"network_type": "NR5G-NSA", "rsrp": -88}],
                             "qeng": TestQeng.SAMPLE,
                             "qspn": self.SAMPLE})
        self.assertEqual(st["cellular"]["sim_operator"], "Mint")
        self.assertEqual(st["cellular"]["operator"], "T-Mobile")
        self.assertEqual(st["cellular"]["operator_label"], "Mint (T-Mobile)")

    def test_build_status_without_qspn_falls_back_to_network(self):
        st = L.build_status({"reachable": True, "country_hint": ["US"],
                             "signals": [{"network_type": "NR5G-NSA", "rsrp": -88}],
                             "qeng": TestQeng.SAMPLE})
        self.assertIsNone(st["cellular"]["sim_operator"])
        self.assertEqual(st["cellular"]["operator_label"], "T-Mobile")


class TestRoaming(unittest.TestCase):
    """Roaming comes from the registration state, not from comparing PLMNs.

    An MVNO rides its host's PLMN, so a Mint SIM on T-Mobile would read as
    roaming under a PLMN comparison; conversely a national roaming agreement
    can share one. AT+CEREG?'s <stat> is the authoritative answer.
    """

    def test_parses_home_and_roaming(self):
        self.assertEqual(L.parse_cereg('\r\n+CEREG: 0,1\r\n\r\nOK\r\n'), "home")
        self.assertEqual(L.parse_cereg('\r\n+CEREG: 0,5\r\n\r\nOK\r\n'), "roaming")

    def test_parses_the_other_3gpp_states(self):
        self.assertEqual(L.parse_cereg('\r\n+CEREG: 0,0\r\n\r\nOK\r\n'), "none")
        self.assertEqual(L.parse_cereg('\r\n+CEREG: 0,2\r\n\r\nOK\r\n'), "searching")
        self.assertEqual(L.parse_cereg('\r\n+CEREG: 0,3\r\n\r\nOK\r\n'), "denied")
        self.assertEqual(L.parse_cereg('\r\n+CEREG: 0,4\r\n\r\nOK\r\n'), "unknown")

    def test_parses_extended_form(self):
        # With <n> set to 2 the modem appends tac/ci/AcT; <stat> stays second.
        self.assertEqual(
            L.parse_cereg('\r\n+CEREG: 2,5,"3C6E","1AE01",7\r\n\r\nOK\r\n'), "roaming")

    def test_missing_or_malformed_is_none(self):
        # None, NOT "home". The caller must not read silence as "definitely
        # not roaming" -- it means the modem did not answer.
        self.assertIsNone(L.parse_cereg('\r\nOK\r\n'))
        self.assertIsNone(L.parse_cereg(''))
        self.assertIsNone(L.parse_cereg(None))
        self.assertIsNone(L.parse_cereg('\r\n+CEREG: 0\r\n\r\nOK\r\n'))
        self.assertIsNone(L.parse_cereg('\r\n+CEREG: 0,x\r\n\r\nOK\r\n'))

    def test_label_marks_the_network_while_roaming(self):
        self.assertEqual(L.operator_label("Mint", "AT&T", "roaming"), "Mint (R:AT&T)")

    def test_label_unmarked_at_home(self):
        self.assertEqual(L.operator_label("Mint", "T-Mobile", "home"), "Mint (T-Mobile)")

    def test_unknown_registration_never_claims_roaming(self):
        # Roaming can cost real money; only show it when actually observed.
        self.assertEqual(L.operator_label("Mint", "T-Mobile", None), "Mint (T-Mobile)")
        self.assertEqual(L.operator_label("Mint", "T-Mobile", "unknown"), "Mint (T-Mobile)")
        self.assertEqual(L.operator_label("Mint", "T-Mobile", "searching"), "Mint (T-Mobile)")

    def test_single_name_roaming_gets_a_bare_marker(self):
        # "R:" needs something to qualify, so with one name it becomes "(R)".
        self.assertEqual(L.operator_label(None, "AT&T", "roaming"), "AT&T (R)")
        self.assertEqual(L.operator_label("Mint", None, "roaming"), "Mint (R)")
        self.assertEqual(L.operator_label("T-Mobile", "T-Mobile", "roaming"), "T-Mobile (R)")

    def test_no_names_stays_none_even_while_roaming(self):
        self.assertIsNone(L.operator_label(None, None, "roaming"))

    def test_build_status_exposes_roaming(self):
        st = L.build_status({"reachable": True, "country_hint": ["US"],
                             "signals": [{"network_type": "LTE", "rsrp": -88}],
                             "qeng": TestQeng.SAMPLE,
                             "qspn": TestSimOperator.SAMPLE,
                             "cereg": '\r\n+CEREG: 0,5\r\n\r\nOK\r\n'})
        self.assertEqual(st["cellular"]["registration"], "roaming")
        self.assertTrue(st["cellular"]["roaming"])
        self.assertEqual(st["cellular"]["operator_label"], "Mint (R:T-Mobile)")

    def test_build_status_without_cereg_is_not_roaming(self):
        st = L.build_status({"reachable": True, "country_hint": ["US"],
                             "signals": [{"network_type": "LTE", "rsrp": -88}],
                             "qeng": TestQeng.SAMPLE,
                             "qspn": TestSimOperator.SAMPLE})
        self.assertIsNone(st["cellular"]["registration"])
        self.assertFalse(st["cellular"]["roaming"])
        self.assertEqual(st["cellular"]["operator_label"], "Mint (T-Mobile)")


class TestPlmnSelection(unittest.TestCase):
    """Several rows for one PLMN are usually ONE network listed per territory.

    234-50 is JT across Guernsey, Jersey and the UK -- not duplicates. A few
    genuinely differ by country, which is what the hint resolves.
    """

    JT = [{"cc": "GB", "brand": "JT", "operator": "JT Group Limited", "status": "Operational"},
          {"cc": "GG", "brand": "JT", "operator": "JT Group Limited", "status": "Operational"},
          {"cc": "JE", "brand": "JT", "operator": "JT Group Limited", "status": "Operational"}]
    # 270-77: genuinely different operators sharing a PLMN across two countries.
    LUX = [{"cc": "BE", "brand": "", "operator": "Proximus Luxembourg S.A.", "status": "Unknown"},
           {"cc": "LU", "brand": "Tango", "operator": "Tango SA", "status": "Operational"}]

    def test_same_network_across_territories_needs_no_hint(self):
        self.assertEqual(L.pick_plmn_name(self.JT), "JT")
        self.assertEqual(L.pick_plmn_name(self.JT, ["GG"]), "JT")

    def test_hint_selects_among_genuinely_different_operators(self):
        self.assertEqual(L.pick_plmn_name(self.LUX, ["LU"]), "Tango")
        self.assertEqual(L.pick_plmn_name(self.LUX, ["BE"]), "Proximus Luxembourg S.A.")

    def test_hint_order_decides_when_several_match(self):
        # Europe/London yields GB,GG,IM,JE -- all four match, so the zone's own
        # primary country must win rather than alphabetical order.
        rows = [{"cc": "GB", "brand": "Umbrella", "operator": "", "status": "Operational"},
                {"cc": "IM", "brand": "Local", "operator": "", "status": "Operational"}]
        self.assertEqual(L.pick_plmn_name(rows, ["GB", "GG", "IM", "JE"]), "Umbrella")
        self.assertEqual(L.pick_plmn_name(rows, ["IM", "GB"]), "Local")

    def test_unmatched_hint_is_ignored_not_filtering(self):
        # THE safety property: roaming abroad with a home-country hint must
        # fall through to normal ranking, never lose the name.
        self.assertEqual(L.pick_plmn_name(self.LUX, ["US"]), "Tango")
        self.assertEqual(L.pick_plmn_name(self.JT, ["US", "CA"]), "JT")

    def test_operational_preferred_over_defunct(self):
        rows = [{"cc": "GB", "brand": "Dead", "operator": "", "status": "Not operational"},
                {"cc": "GB", "brand": "Live", "operator": "", "status": "Operational"}]
        self.assertEqual(L.pick_plmn_name(rows), "Live")

    def test_operator_used_when_brand_is_empty(self):
        # A third of upstream rows carry no brand; dropping to None there would
        # lose a name that is present.
        rows = [{"cc": "US", "brand": "", "operator": "Some Telecom", "status": "Operational"}]
        self.assertEqual(L.pick_plmn_name(rows), "Some Telecom")

    def test_nameless_rows_are_skipped_entirely(self):
        rows = [{"cc": "US", "brand": "", "operator": "", "status": "Operational"},
                {"cc": "CA", "brand": "Real", "operator": "", "status": "Unknown"}]
        self.assertEqual(L.pick_plmn_name(rows), "Real")

    def test_no_rows_is_none(self):
        self.assertIsNone(L.pick_plmn_name([]))
        self.assertIsNone(L.pick_plmn_name(None))
        self.assertIsNone(L.pick_plmn_name([{"cc": "US", "brand": "", "operator": ""}]))

    def test_selection_is_deterministic(self):
        rows = [{"cc": "ZZ", "brand": "B", "operator": "", "status": "Operational"},
                {"cc": "AA", "brand": "A", "operator": "", "status": "Operational"}]
        self.assertEqual(L.pick_plmn_name(rows), L.pick_plmn_name(list(reversed(rows))))


class TestCountryHint(unittest.TestCase):
    """The hint comes from the file weather.sh publishes.

    Not geoclue: its Location interface answers with coordinates and no country
    at all. Not tzdata: that reports where the machine is CONFIGURED rather
    than where it is. There is deliberately no fallback -- see
    TestUnknownNetwork for what happens without a hint.
    """

    def _file(self, body):
        import tempfile
        f = tempfile.NamedTemporaryFile("w", delete=False)
        f.write(body)
        f.close()
        return f.name

    def test_reads_a_country_code(self):
        self.assertEqual(L.country_hint(self._file("US\n")), ["US"])
        self.assertEqual(L.country_hint(self._file("gb")), ["GB"])
        self.assertEqual(L.country_hint(self._file("  JE  \n")), ["JE"])

    def test_missing_file_is_no_hint(self):
        self.assertEqual(L.country_hint("/nonexistent/country"), [])

    def test_corrupt_or_partial_write_is_no_hint(self):
        # A torn write must read as "no hint", never as a country -- an
        # invented one would silently name the wrong operator.
        self.assertEqual(L.country_hint(self._file("")), [])
        self.assertEqual(L.country_hint(self._file("U")), [])
        self.assertEqual(L.country_hint(self._file("USA")), [])
        self.assertEqual(L.country_hint(self._file("U1")), [])
        self.assertEqual(L.country_hint(self._file("{\"country\":\"US\"}")), [])


class TestUnknownNetwork(unittest.TestCase):
    """With no country hint the network is not named at all.

    Rows for one PLMN can genuinely differ by country, so without knowing where
    the device is, any name is a guess -- and a confidently wrong carrier reads
    worse than an honest blank.
    """

    TABLE = {"310-260": [{"cc": "US", "brand": "T-Mobile", "operator": "T-Mobile US",
                          "status": "Operational"}]}

    def test_no_hint_yields_na(self):
        self.assertEqual(L.operator_from_plmn("310", "260", [], self.TABLE), "N/A")
        self.assertEqual(L.operator_from_plmn("310", "260", None, self.TABLE), "N/A")

    def test_hint_yields_the_name(self):
        self.assertEqual(L.operator_from_plmn("310", "260", ["US"], self.TABLE), "T-Mobile")

    def test_label_shows_the_sim_brand_beside_na(self):
        # The SIM's own name comes from AT+QSPN and needs no country, so it
        # still shows: "Mint ( N/A )" rather than nothing at all.
        self.assertEqual(L.operator_label("Mint", "N/A"), "Mint (N/A)")

    def test_build_status_with_no_country_shows_na(self):
        # The end-to-end shape the display uses: the SIM brand still resolves
        # (AT+QSPN needs no country), the network does not.
        st = L.build_status({"reachable": True, "country_hint": [],
                             "signals": [{"network_type": "LTE", "rsrp": -88}],
                             "qeng": TestQeng.SAMPLE,
                             "qspn": TestSimOperator.SAMPLE})
        self.assertEqual(st["cellular"]["operator"], "N/A")
        self.assertEqual(st["cellular"]["sim_operator"], "Mint")
        self.assertEqual(st["cellular"]["operator_label"], "Mint (N/A)")
        # The PLMN itself is a fact and must survive regardless.
        self.assertEqual(st["cellular"]["plmn"], "310-260")

    def test_missing_plmn_is_still_none(self):
        self.assertIsNone(L.operator_from_plmn(None, None, ["US"], self.TABLE))


class TestPlmnTableFile(unittest.TestCase):
    """Smoke test against the vendored table actually shipped."""

    def test_vendored_table_loads_and_resolves(self):
        import os
        path = os.path.join(os.path.dirname(os.path.abspath(L.__file__)),
                            "plmn-names.json")
        table = L.load_plmn_table(path)
        self.assertGreater(len(table), 3000)
        self.assertEqual(L.operator_from_plmn("310", "260", ["US"], table), "T-Mobile")
        self.assertEqual(L.operator_from_plmn("310", "410", ["US"], table), "AT&T")
        self.assertEqual(L.operator_from_plmn("234", "15", ["GB"], table), "Vodafone UK")

    def test_missing_table_degrades_to_the_number(self):
        table = L.load_plmn_table("/nonexistent/plmn-names.json")
        self.assertEqual(table, {})
        self.assertEqual(L.operator_from_plmn("310", "260", ["US"], table), "310-260")
