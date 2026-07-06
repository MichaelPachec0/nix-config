from __future__ import annotations
import unittest
import fanbridge as fb


class TestParseFrame(unittest.TestCase):
    FRAME = (
        "ryzen_monitor_ng,host=thanatos,name=Cores cores_maxtemperature=82.00,cores_totalpower=15.000\n"
        "ryzen_monitor_ng,host=thanatos,name=Package cpu_thm=80.00,cpu_thmlimit=95i,"
        "package_peaktemperature=101.00,cpu_coupled=true\n"
    )

    def test_numeric_fields(self) -> None:
        f = fb.parse_frame(self.FRAME)
        self.assertEqual(f["cpu_thm"], 80.0)
        self.assertEqual(f["package_peaktemperature"], 101.0)
        self.assertEqual(f["cpu_thmlimit"], 95.0)  # trailing i stripped
        self.assertEqual(f["cores_maxtemperature"], 82.0)

    def test_skips_non_numeric(self) -> None:
        f = fb.parse_frame(self.FRAME)
        self.assertNotIn("cpu_coupled", f)  # "true" is not a float

    def test_empty_and_garbage(self) -> None:
        self.assertEqual(fb.parse_frame(""), {})
        self.assertEqual(fb.parse_frame("no equals here"), {})


class TestResolveMode(unittest.TestCase):
    def test_override_wins(self) -> None:
        self.assertEqual(fb.resolve_mode("quiet", True), "quiet")
        self.assertEqual(fb.resolve_mode("perf", False), "perf")

    def test_auto_by_ac(self) -> None:
        self.assertEqual(fb.resolve_mode(None, True), "perf")
        self.assertEqual(fb.resolve_mode(None, False), "quiet")

    def test_bad_override_falls_back_to_auto(self) -> None:
        self.assertEqual(fb.resolve_mode("bogus", True), "perf")


INIT = fb.State(ema=None, hot_since=None)


def mk(**kw: object) -> fb.Inputs:
    base: dict[str, object] = dict(cpu_thm=None, peak=None, tctl=None, frame_age=0.0,
                                   ac_online=True, override=None, now=0.0)
    base.update(kw)
    return fb.Inputs(**base)  # type: ignore[arg-type]


class TestControlPath(unittest.TestCase):
    def test_first_tick_seeds_ema_to_base(self) -> None:
        d = fb.decide(mk(cpu_thm=40.0), INIT)
        self.assertEqual(d.state.ema, 40.0)
        self.assertEqual(d.published_mc, 40000)  # perf offset 0

    def test_ema_smooths(self) -> None:
        d = fb.decide(mk(cpu_thm=60.0), fb.State(ema=40.0, hot_since=None))
        # 0.4*60 + 0.6*40 = 48
        self.assertEqual(d.state.ema, 48.0)
        self.assertEqual(d.published_mc, 48000)

    def test_stale_falls_back_to_tctl(self) -> None:
        d = fb.decide(mk(cpu_thm=40.0, tctl=90.0, frame_age=99.0), INIT)
        self.assertEqual(d.state.ema, 90.0)  # used tctl, not cpu_thm

    def test_quiet_offset_lowers_published(self) -> None:
        perf = fb.decide(mk(cpu_thm=70.0, ac_online=True), INIT)
        quiet = fb.decide(mk(cpu_thm=70.0, ac_online=False), INIT)
        self.assertEqual(perf.published_mc - quiet.published_mc,
                         int(fb.QUIET_OFFSET_C * 1000))

    def test_total_sensor_loss_fails_safe(self) -> None:
        d = fb.decide(mk(cpu_thm=None, tctl=None, frame_age=99.0), INIT)
        self.assertEqual(d.published_mc, fb.FAIL_SAFE_MC)
        self.assertIs(d.state, INIT)   # fail-safe returns the incoming state unchanged

    def test_clamp_low(self) -> None:
        d = fb.decide(mk(cpu_thm=2.0, ac_online=False), INIT)  # 2 - 9 = -7 -> 0
        self.assertEqual(d.published_mc, 0)

    def test_fallback_ignores_quiet_offset(self) -> None:
        # SMU stale -> Tctl fallback publishes EMA(Tctl) with NO profile offset,
        # even in quiet mode (design decision #3).
        d = fb.decide(mk(cpu_thm=None, tctl=90.0, frame_age=99.0,
                         ac_online=False), INIT)
        self.assertEqual(d.published_mc, 90000)


class TestSafetyOverride(unittest.TestCase):
    def _hot(self, now: float, hot_since: float | None) -> fb.Decision:
        # Tctl over threshold; smoothing already warm at a mild temp.
        st = fb.State(ema=70.0, hot_since=hot_since)
        return fb.decide(mk(cpu_thm=70.0, tctl=98.0, now=now), st)

    def test_hot_sets_hot_since_but_not_yet_forced(self) -> None:
        d = self._hot(now=100.0, hot_since=None)
        self.assertEqual(d.state.hot_since, 100.0)
        self.assertNotEqual(d.published_mc, int(fb.FORCE_MAX_C * 1000))

    def test_not_yet_sustained(self) -> None:
        d = self._hot(now=102.9, hot_since=100.0)  # 2.9s < 3s
        self.assertNotEqual(d.published_mc, int(fb.FORCE_MAX_C * 1000))
        self.assertEqual(d.state.hot_since, 100.0)   # latch preserves the original start time

    def test_sustained_forces_max(self) -> None:
        d = self._hot(now=103.1, hot_since=100.0)  # 3.1s >= 3s
        self.assertEqual(d.published_mc, int(fb.FORCE_MAX_C * 1000))
        self.assertIsNotNone(d.state.ema)   # EMA stays warm even when force-max fires

    def test_peak_also_trips(self) -> None:
        st = fb.State(ema=70.0, hot_since=100.0)
        d = fb.decide(mk(cpu_thm=70.0, peak=100.5, now=104.0), st)
        self.assertEqual(d.published_mc, int(fb.FORCE_MAX_C * 1000))

    def test_cooling_resets_window(self) -> None:
        st = fb.State(ema=70.0, hot_since=100.0)
        d = fb.decide(mk(cpu_thm=70.0, tctl=80.0, peak=80.0, now=105.0), st)
        self.assertIsNone(d.state.hot_since)

    def test_force_max_bypasses_quiet_offset(self) -> None:
        st = fb.State(ema=70.0, hot_since=100.0)
        d = fb.decide(mk(cpu_thm=70.0, tctl=98.0, ac_online=False, now=104.0), st)
        self.assertEqual(d.published_mc, int(fb.FORCE_MAX_C * 1000))  # no -9 applied


import os
import tempfile
import main as drv


class TestDriverHelpers(unittest.TestCase):
    def test_resolve_tctl_path(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            h = os.path.join(root, "hwmon9")
            os.mkdir(h)
            with open(os.path.join(h, "name"), "w") as f:
                f.write("zenpower\n")
            with open(os.path.join(h, "temp2_label"), "w") as f:
                f.write("Tctl\n")
            with open(os.path.join(h, "temp2_input"), "w") as f:
                f.write("96000\n")
            self.assertEqual(drv.resolve_tctl_path(root),
                             os.path.join(h, "temp2_input"))

    def test_resolve_tctl_path_absent(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            self.assertIsNone(drv.resolve_tctl_path(root))

    def test_read_millideg(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            p = os.path.join(root, "t")
            with open(p, "w") as f:
                f.write("96000\n")
            self.assertEqual(drv.read_millideg(p), 96.0)
            self.assertIsNone(drv.read_millideg(os.path.join(root, "missing")))
            self.assertIsNone(drv.read_millideg(None))

    def test_read_override(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            p = os.path.join(root, "mode")
            self.assertIsNone(drv.read_override(p))  # absent
            with open(p, "w") as f:
                f.write("perf\n")
            self.assertEqual(drv.read_override(p), "perf")
            with open(p, "w") as f:
                f.write("bogus\n")
            self.assertIsNone(drv.read_override(p))  # invalid -> None

    def test_atomic_write(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            p = os.path.join(root, "out")
            drv.atomic_write(p, "84000\n", 0o644)
            with open(p) as f:
                self.assertEqual(f.read(), "84000\n")


if __name__ == "__main__":
    unittest.main()
