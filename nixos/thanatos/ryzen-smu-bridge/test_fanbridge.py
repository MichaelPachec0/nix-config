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


if __name__ == "__main__":
    unittest.main()
