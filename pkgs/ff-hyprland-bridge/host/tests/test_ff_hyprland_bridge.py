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


CLIENTS = [
    {"address": "0xa1", "pid": 500, "monitor": 1, "size": [1900, 1000], "title": "Video - YouTube", "class": "firefox-dev"},
    {"address": "0xa2", "pid": 500, "monitor": 0, "size": [1200, 800], "title": "Mail", "class": "firefox-dev"},
    {"address": "0xb1", "pid": 777, "monitor": 1, "size": [800, 600], "title": "Other profile", "class": "firefox"},
    {"address": "0xc1", "pid": 42, "monitor": 2, "size": [800, 600], "title": "kitty", "class": "kitty"},
]
MONITORS = [{"id": 0, "name": "eDP-1"}, {"id": 1, "name": "HDMI-A-1"}, {"id": 2, "name": "DP-2"}, {"id": 3, "name": "DP-6"}]


class FakeHyprctl:
    def __init__(self, clients=None, monitors=None):
        self.clients = clients if clients is not None else [dict(c) for c in CLIENTS]
        self.monitors = monitors if monitors is not None else MONITORS
        self.calls = []

    def __call__(self, *args):
        self.calls.append(args)
        if args[:2] == ("clients", "-j"):
            return json.dumps(self.clients)
        if args[:2] == ("monitors", "-j"):
            return json.dumps(self.monitors)
        return ""


def make_state(fake=None):
    fake = fake or FakeHyprctl()
    st = b.HyprState(hyprctl=fake, ppid=500, sysfs=FIX_SYSFS, log=lambda m: None)
    st.refresh_monitors()
    st.refresh_clients()
    return st, fake


class HyprStateTest(unittest.TestCase):
    def test_filters_to_parent_pid(self):
        st, _ = make_state()
        self.assertEqual(set(st.clients), {"0xa1", "0xa2"})

    def test_hdr_for_uses_monitor_edid(self):
        st, _ = make_state()
        self.assertTrue(st.hdr_for("0xa1"))    # HDMI-A-1
        self.assertFalse(st.hdr_for("0xa2"))   # eDP-1
        self.assertIsNone(st.hdr_for("0xzz"))  # unknown

    def test_set_title_and_drop(self):
        st, _ = make_state()
        st.set_title("0xa2", "Inbox")
        self.assertEqual(st.clients["0xa2"]["title"], "Inbox")
        st.set_title("0xzz", "ignored")
        self.assertNotIn("0xzz", st.clients)
        st.drop("0xa2")
        self.assertNotIn("0xa2", st.clients)


class MapperTest(unittest.TestCase):
    def test_unique_title_maps(self):
        st, _ = make_state()
        m = b.Mapper()
        self.assertEqual(m.learn(st, 7, "Video - YouTube"), "0xa1")
        self.assertEqual(m.address_for(7), "0xa1")

    def test_tie_stays_pending_until_retitle(self):
        fake = FakeHyprctl(clients=[dict(c, title="New Tab") for c in CLIENTS[:2]])
        st, _ = make_state(fake)
        m = b.Mapper()
        self.assertIsNone(m.learn(st, 1, "New Tab"))
        self.assertIsNone(m.learn(st, 2, "New Tab"))
        st.set_title("0xa2", "Mail")
        self.assertEqual(m.learn(st, 2, "Mail"), "0xa2")
        # only one unmapped client and one pending window left: elimination
        self.assertEqual(m.learn(st, 1, "New Tab"), "0xa1")

    def test_closed_address_is_forgotten(self):
        st, _ = make_state()
        m = b.Mapper()
        m.learn(st, 7, "Video - YouTube")
        m.forget_address("0xa1")
        self.assertIsNone(m.address_for(7))

    def test_divergence_relearns_after_two_strikes(self):
        st, _ = make_state()
        m = b.Mapper()
        m.learn(st, 7, "Video - YouTube")
        # the extension now says window 7 is titled "Mail", and 0xa2 is exactly that
        m.check_divergence(st, {7: "Mail"})
        self.assertEqual(m.address_for(7), "0xa1")  # one strike, keep
        m.check_divergence(st, {7: "Mail"})
        self.assertEqual(m.address_for(7), "0xa2")  # relearned


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.fake = FakeHyprctl()
        self.state, _ = make_state(self.fake)
        self.sent = []
        self.bridge = b.Bridge(self.state, b.Mapper(), send=self.sent.append, load_config=lambda: dict(b.DEFAULTS))

    def hdr_msgs(self):
        return [m for m in self.sent if m["type"] == "hdr"]

    def test_window_message_maps_and_answers(self):
        self.bridge.on_message({"type": "window", "windowId": 7, "title": "Video - YouTube"})
        self.assertEqual(self.hdr_msgs(), [{"type": "hdr", "windowId": 7, "hdr": True, "monitor": "HDMI-A-1"}])

    def test_unresolved_window_sends_nothing(self):
        self.bridge.on_message({"type": "hdr-query", "windowId": 9, "title": "nowhere"})
        self.assertEqual(self.hdr_msgs(), [])

    def test_move_changes_answer_once(self):
        self.bridge.on_message({"type": "window", "windowId": 7, "title": "Video - YouTube"})
        self.fake.clients[0]["monitor"] = 0  # dragged to eDP-1
        for _ in range(10):
            self.bridge.on_event("movewindowv2>>0xa1,1,1")
        calls_before = len(self.fake.calls)
        self.bridge.flush()
        self.assertEqual(len(self.fake.calls) - calls_before, 1)  # one clients -j for the burst
        self.assertEqual([m["hdr"] for m in self.hdr_msgs()], [True, False])
        self.bridge.flush()
        self.assertEqual(len(self.hdr_msgs()), 2)  # unchanged -> nothing new

    def test_monitor_event_refreshes_monitors_and_capability(self):
        self.bridge.on_event("monitorremoved>>HDMI-A-1")
        self.assertTrue(self.bridge.pending_monitor)
        self.bridge.flush()
        self.assertIn(("monitors", "-j"), self.fake.calls)

    def test_windowtitlev2_feeds_learner(self):
        self.fake.clients[1]["title"] = "New Tab"
        self.state.refresh_clients()
        self.bridge.on_message({"type": "window", "windowId": 3, "title": "Inbox"})
        self.assertEqual(self.hdr_msgs(), [])
        self.bridge.on_event("windowtitlev2>>0xa2,Inbox")
        self.assertEqual(self.hdr_msgs(), [{"type": "hdr", "windowId": 3, "hdr": False, "monitor": "eDP-1"}])

    def test_closewindow_drops_mapping(self):
        self.bridge.on_message({"type": "window", "windowId": 7, "title": "Video - YouTube"})
        self.bridge.on_event("closewindow>>0xa1")
        self.assertIsNone(self.bridge.mapper.address_for(7))

    def test_state_applies_tags_through_mapping(self):
        self.bridge.on_message({"type": "state", "windowId": 7, "title": "Video - YouTube", "playing": True,
                                "rects": [{"x": 10, "y": 20, "w": 100, "h": 50}], "outer": {"w": 1900, "h": 1000}})
        evals = [c for c in self.fake.calls if c[0] == "eval"]
        self.assertEqual(len(evals), 1)
        self.assertIn("+hyprglass_rect:10,20,100,50", evals[0][1])
        self.assertIn("address:0xa1", evals[0][1])

    def test_hdr_disabled_sends_no_hdr(self):
        cfg = dict(b.DEFAULTS, hdrEnable=False)
        bridge = b.Bridge(self.state, b.Mapper(), send=self.sent.append, load_config=lambda: cfg)
        bridge.on_message({"type": "window", "windowId": 7, "title": "Video - YouTube"})
        self.assertEqual(self.hdr_msgs(), [])


class Socket2PathTest(unittest.TestCase):
    def test_path_from_env(self):
        env = {"XDG_RUNTIME_DIR": "/run/user/1000", "HYPRLAND_INSTANCE_SIGNATURE": "sig"}
        self.assertEqual(b.socket2_path(env), "/run/user/1000/hypr/sig/.socket2.sock")
        self.assertIsNone(b.socket2_path({}))


if __name__ == "__main__":
    unittest.main()
