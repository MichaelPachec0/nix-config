import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import ff_hyprland_bridge as b  # noqa: E402

FIX = os.path.join(HERE, "fixtures", "edid")


def fixture(name):
    with open(os.path.join(FIX, name + ".bin"), "rb") as f:
        return f.read()


# A fake /sys/class/drm with the real EDIDs under Hyprland's connector names.
FIX_SYSFS = tempfile.mkdtemp()
for _name in ("eDP-1", "HDMI-A-1", "DP-2", "DP-6"):
    _d = os.path.join(FIX_SYSFS, f"card1-{_name}")
    os.makedirs(_d, exist_ok=True)
    with open(os.path.join(_d, "status"), "w") as _f:
        _f.write("connected\n")
    with open(os.path.join(_d, "edid"), "wb") as _f:
        _f.write(fixture(_name))


class EdidTest(unittest.TestCase):
    def test_hdr_monitors_are_capable(self):
        self.assertTrue(b.edid_hdr_capable(fixture("HDMI-A-1")))  # ASUS VG259QM
        self.assertTrue(b.edid_hdr_capable(fixture("DP-2")))      # KTC H27S17

    def test_sdr_monitors_are_not(self):
        self.assertFalse(b.edid_hdr_capable(fixture("eDP-1")))    # panel, base block only
        self.assertFalse(b.edid_hdr_capable(fixture("DP-6")))     # ASUS VG279, CTA block, no HDR

    def test_garbage_is_not_capable_and_does_not_raise(self):
        self.assertFalse(b.edid_hdr_capable(b""))
        self.assertFalse(b.edid_hdr_capable(b"\x00" * 64))
        self.assertFalse(b.edid_hdr_capable(fixture("DP-2")[:200]))  # truncated extension


class SysfsTest(unittest.TestCase):
    def make(self, root, card, name, status, edid):
        d = os.path.join(root, f"card{card}-{name}")
        os.makedirs(d)
        with open(os.path.join(d, "status"), "w") as f:
            f.write(status + "\n")
        with open(os.path.join(d, "edid"), "wb") as f:
            f.write(edid)

    def test_prefers_connected_card_with_edid(self):
        with tempfile.TemporaryDirectory() as root:
            self.make(root, 0, "DP-2", "disconnected", b"")
            self.make(root, 1, "DP-2", "connected", fixture("DP-2"))
            self.assertEqual(b.connector_edid_path("DP-2", root), os.path.join(root, "card1-DP-2", "edid"))
            self.assertTrue(b.monitor_hdr_capable("DP-2", root, log=lambda m: None))

    def test_missing_connector(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertIsNone(b.connector_edid_path("DP-9", root))
            logged = []
            self.assertFalse(b.monitor_hdr_capable("DP-9", root, log=logged.append))
            self.assertEqual(len(logged), 1)


if __name__ == "__main__":
    unittest.main()
