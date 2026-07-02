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


if __name__ == "__main__":
    unittest.main()
