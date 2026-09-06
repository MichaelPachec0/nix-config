#!/usr/bin/env python3
"""Native-messaging host for ff-hyprland-bridge.

Receives per-window playback state from the WebExtension and applies or
clears Hyprland window tags/props through `hyprctl eval` (the Lua config
manager rejects `hyprctl dispatch`, so eval is the only runtime entry).

Actions (config key playbackAction):
  strip  whole window: +hyprglass_disabled tag, no_blur 1, no_dim 1
  undim  whole window: no_dim 1
  rect   no_dim 1 plus one `hyprglass_rect:x,y,w,h` tag per visible playing
         video; the plugin's dim overlay then dims everything but the rects.
         With playback reported but no visible rect, `rectFallback`
         (none|undim|strip) decides what, if anything, happens.

HDR (config key hdrEnable, default true):
  Answers, per Firefox window, whether the monitor it sits on is HDR-capable
  (EDID: SMPTE ST 2084 EOTF plus BT.2020 colorimetry). The extension turns
  that into the page's video-dynamic-range answer. Firefox's content process
  cannot do this itself on Wayland: it has no window position and resolves
  every window to the first wl_output.

Every failure degrades to doing nothing: the compositor keeps R2 mask-mode
behaviour, which is already visually correct without this bridge.
"""
import glob
import json
import os
import socket
import struct
import subprocess
import sys
import threading

CONFIG_PATH = os.path.expanduser("~/.config/ff-hyprland-bridge.json")
# Debug aid: set FF_HYPRLAND_BRIDGE_LOG=<file> in Firefox's environment and
# the host appends one line per message in either direction plus its startup
# facts (ppid, socket2 path, client count). Off when unset.
TRACE_PATH = os.environ.get("FF_HYPRLAND_BRIDGE_LOG")
RECT_PREFIX = "hyprglass_rect:"

DEFAULTS = {
    "playbackAction": "rect",
    "playSignal": "activeTab",
    "pauseGraceMs": 3000,
    "rectFallback": "none",
    "rectRateHz": 10,
    "hdrEnable": True,
}


def load_config():
    cfg = dict(DEFAULTS)
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            cfg.update(json.load(f))
    except (OSError, ValueError):
        pass
    return cfg


def trace(kind, obj):
    if not TRACE_PATH:
        return
    try:
        with open(TRACE_PATH, "a", encoding="utf-8") as f:
            f.write(f"{kind} {json.dumps(obj)}\n")
    except OSError:
        pass


def read_message():
    raw = sys.stdin.buffer.read(4)
    if len(raw) < 4:
        return None
    (length,) = struct.unpack("<I", raw)
    if length > 1 << 20:
        return None
    data = sys.stdin.buffer.read(length)
    if len(data) < length:
        return None
    try:
        msg = json.loads(data)
    except ValueError:
        return None
    trace("in", msg)
    return msg


_SEND_LOCK = threading.Lock()  # the main loop and the socket2 thread both send


def send_message(obj):
    trace("out", obj)
    data = json.dumps(obj).encode()
    with _SEND_LOCK:
        sys.stdout.buffer.write(struct.pack("<I", len(data)))
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()


def hyprctl(*args):
    try:
        return subprocess.run(
            ["hyprctl", *args], capture_output=True, text=True, timeout=5
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


# --- EDID: is this connector's monitor HDR-capable? --------------------------

EDID_MAGIC = bytes.fromhex("00ffffffffffff00")
CTA_TAG = 0x02
CTA_EXTENDED = 7
CTA_EXT_COLORIMETRY = 0x05
CTA_EXT_HDR_STATIC = 0x06
EOTF_ST2084 = 0x04              # HDR static metadata byte 1, bit 2
COLORIMETRY_BT2020_MASK = 0xE0  # byte 1, bits 5..7: BT2020cYCC / YCC / RGB


def print_err(msg):
    sys.stderr.write(f"ff_hyprland_bridge: {msg}\n")
    sys.stderr.flush()


def edid_hdr_capable(data):
    """SMPTE ST 2084 EOTF and BT.2020 colorimetry both present in a CTA-861
    extension block. This is the pair Hyprland's supportsHDR() needs, so
    "capable" here means "Hyprland will flip this output to HDR". Anything
    malformed is not capable; never raises."""
    try:
        if len(data) < 128 or data[:8] != EDID_MAGIC:
            return False
        pq = bt2020 = False
        for i in range(1, data[126] + 1):
            blk = data[128 * i:128 * (i + 1)]
            if len(blk) < 128 or blk[0] != CTA_TAG:
                continue
            end = blk[2] if blk[2] >= 4 else 127
            p = 4
            while p < end:
                tag, ln = blk[p] >> 5, blk[p] & 0x1F
                body = blk[p + 1:p + 1 + ln]
                if tag == CTA_EXTENDED and ln >= 2:
                    if body[0] == CTA_EXT_HDR_STATIC and body[1] & EOTF_ST2084:
                        pq = True
                    elif body[0] == CTA_EXT_COLORIMETRY and body[1] & COLORIMETRY_BT2020_MASK:
                        bt2020 = True
                p += 1 + ln
        return pq and bt2020
    except Exception:
        return False


def connector_edid_path(name, sysfs="/sys/class/drm"):
    """/sys/class/drm/card*-<name>/edid, preferring a connected card with a
    non-empty EDID (MST and multi-GPU expose the same connector name on more
    than one card). sysfs reports binary attributes as size 0, so
    non-emptiness is probed with a one-byte read, not stat."""
    candidates = sorted(glob.glob(os.path.join(sysfs, f"card*-{name}", "edid")))
    for path in candidates:
        try:
            with open(os.path.join(os.path.dirname(path), "status")) as f:
                status = f.read().strip()
            with open(path, "rb") as f:
                has_data = bool(f.read(1))
            if status == "connected" and has_data:
                return path
        except OSError:
            continue
    return candidates[0] if candidates else None


def monitor_hdr_capable(name, sysfs="/sys/class/drm", log=print_err):
    path = connector_edid_path(name, sysfs)
    if not path:
        log(f"no EDID node for connector {name}; treating as SDR")
        return False
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        log(f"cannot read {path}: {e}; treating as SDR")
        return False
    if not data:
        log(f"empty EDID at {path}; treating as SDR")
        return False
    return edid_hdr_capable(data)


# --- Hyprland state: this Firefox's windows, monitors, HDR per monitor -------

class HyprState:
    """Clients of THIS Firefox (pid == our parent: Firefox spawns the host),
    monitor id -> connector name, and cached HDR capability per connector."""

    def __init__(self, hyprctl=hyprctl, ppid=None, sysfs="/sys/class/drm", log=print_err):
        self.hyprctl = hyprctl
        self._ppid = ppid if ppid is not None else os.getppid()
        self._sysfs = sysfs
        self._log = log
        self.lock = threading.RLock()
        self.clients = {}   # address -> {"title", "monitor", "size"}
        self.monitors = {}  # id -> name
        self.capable = {}   # name -> bool

    def _json(self, *args):
        try:
            return json.loads(self.hyprctl(*args) or "[]")
        except ValueError:
            return None

    def refresh_clients(self):
        data = self._json("clients", "-j")
        if data is None:
            return  # keep the last good table
        with self.lock:
            self.clients = {
                c["address"]: {"title": c.get("title", ""), "monitor": c.get("monitor"), "size": c.get("size") or []}
                for c in data
                if c.get("pid") == self._ppid and c.get("address")
            }

    def refresh_monitors(self):
        data = self._json("monitors", "-j")
        if data is None:
            return
        with self.lock:
            self.monitors = {m["id"]: m["name"] for m in data if "id" in m and "name" in m}
            self.capable = {}

    def set_title(self, address, title):
        with self.lock:
            if address in self.clients:
                self.clients[address]["title"] = title

    def drop(self, address):
        with self.lock:
            self.clients.pop(address, None)

    def client(self, address):
        with self.lock:
            return self.clients.get(address)

    def hdr_for(self, address):
        with self.lock:
            c = self.clients.get(address)
            if not c:
                return None
            name = self.monitors.get(c.get("monitor"))
            if name is None:
                return None
            if name not in self.capable:
                self.capable[name] = monitor_hdr_capable(name, self._sysfs, self._log)
            return self.capable[name]


class Mapper:
    """windowId (extension) -> address (Hyprland), learned from titles."""

    def __init__(self):
        self.mapping = {}   # window_id -> address
        self.pending = {}   # window_id -> last reported title
        self.strikes = {}   # window_id -> consecutive divergence count

    def address_for(self, window_id):
        return self.mapping.get(window_id)

    def forget_address(self, address):
        for wid in [w for w, a in self.mapping.items() if a == address]:
            del self.mapping[wid]
            self.strikes.pop(wid, None)

    def learn(self, state, window_id, title):
        with state.lock:
            addr = self.mapping.get(window_id)
            if addr in state.clients:
                return addr
            self.mapping.pop(window_id, None)
            self.pending[window_id] = title
            mapped = set(self.mapping.values())
            exact = [a for a, c in state.clients.items() if c["title"] == title and a not in mapped]
            if len(exact) == 1:
                return self._map(window_id, exact[0])
            unmapped = [a for a in state.clients if a not in mapped]
            if len(unmapped) == 1 and len(self.pending) == 1:
                return self._map(window_id, unmapped[0])
            return None

    def _map(self, window_id, address):
        self.mapping[window_id] = address
        self.pending.pop(window_id, None)
        self.strikes.pop(window_id, None)
        return address

    def check_divergence(self, state, reported):
        """reported: window_id -> title the extension last sent. A mapping
        whose client title differs while another client matches exactly, two
        checks in a row, is dropped and relearned (bad tie-break guard)."""
        with state.lock:
            for wid, title in reported.items():
                addr = self.mapping.get(wid)
                c = state.clients.get(addr)
                if not c or c["title"] == title:
                    self.strikes.pop(wid, None)
                    continue
                others = [a for a, cc in state.clients.items() if a != addr and cc["title"] == title]
                if not others:
                    self.strikes.pop(wid, None)
                    continue
                n = self.strikes.get(wid, 0) + 1
                if n < 2:
                    self.strikes[wid] = n
                    continue
                del self.mapping[wid]
                self.strikes.pop(wid, None)
                self.learn(state, wid, title)


# --- Bridge controller ------------------------------------------------------

REFRESH_EVENTS = {
    "openwindow", "closewindow", "movewindow", "movewindowv2",
    "moveworkspace", "moveworkspacev2", "focusedmon", "focusedmonv2",
    "monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2",
}
MONITOR_EVENTS = {"monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2"}
DEBOUNCE_S = 0.15


class Bridge:
    """Glue: port messages in, socket2 events in, hdr messages and playback
    tags out. Thread-safe through state.lock; every public method may be
    called from either thread."""

    def __init__(self, state, mapper, send, load_config=load_config):
        self.state = state
        self.mapper = mapper
        self._send = send
        self._load_config = load_config
        self.applied = {}          # address -> Applied
        self.last_hdr = {}         # window_id -> bool last sent
        self.reported = {}         # window_id -> last title from the extension
        self.pending_refresh = False
        self.pending_monitor = False

    # -- inbound: extension ---------------------------------------------------

    def on_message(self, msg):
        kind = msg.get("type")
        if kind not in ("state", "window", "hdr-query"):
            return
        wid = msg.get("windowId")
        title = str(msg.get("title", ""))
        if wid is None:
            return
        with self.state.lock:
            self.reported[wid] = title
            self.state.refresh_clients()
            address = self.mapper.learn(self.state, wid, title)
            if kind == "state":
                client = self.state.client(address) if address else None
                if client:
                    applied = self.applied.setdefault(address, Applied())
                    apply_state(address, client, bool(msg.get("playing")), msg.get("rects") or [],
                                msg.get("outer"), self._load_config(), applied, run=self.state.hyprctl)
            self.publish()

    # -- inbound: Hyprland socket2 --------------------------------------------

    def on_event(self, line):
        name, sep, payload = line.partition(">>")
        if not sep:
            return
        if name == "windowtitlev2":
            addr, _, title = payload.partition(",")
            with self.state.lock:
                self.state.set_title(self._hex(addr), title)
                for wid, t in list(self.mapper.pending.items()):
                    self.mapper.learn(self.state, wid, t)
                self.publish()
            return
        if name == "closewindow":
            addr = self._hex(payload)
            with self.state.lock:
                self.state.drop(addr)
                self.mapper.forget_address(addr)
                self.applied.pop(addr, None)
        if name in REFRESH_EVENTS:
            self.pending_refresh = True
            if name in MONITOR_EVENTS:
                self.pending_monitor = True

    @staticmethod
    def _hex(addr):
        addr = addr.strip()
        return addr if addr.startswith("0x") else "0x" + addr

    def flush(self):
        """Debounced refresh: one hyprctl clients -j per event burst."""
        if not self.pending_refresh:
            return
        self.pending_refresh = False
        with self.state.lock:
            if self.pending_monitor:
                self.pending_monitor = False
                self.state.refresh_monitors()
            self.state.refresh_clients()
            for addr in [a for a in set(self.mapper.mapping.values()) if a not in self.state.clients]:
                self.mapper.forget_address(addr)
                self.applied.pop(addr, None)
            self.mapper.check_divergence(self.state, self.reported)
            for wid, t in list(self.mapper.pending.items()):
                self.mapper.learn(self.state, wid, t)
            self.publish()

    # -- outbound -------------------------------------------------------------

    def publish(self):
        if not self._load_config().get("hdrEnable", True):
            return
        with self.state.lock:
            for wid, addr in list(self.mapper.mapping.items()):
                hdr = self.state.hdr_for(addr)
                if hdr is None or self.last_hdr.get(wid) == hdr:
                    continue
                self.last_hdr[wid] = hdr
                c = self.state.client(addr) or {}
                self._send({"type": "hdr", "windowId": wid, "hdr": hdr,
                            "monitor": self.state.monitors.get(c.get("monitor"), "")})
            for wid in [w for w in self.last_hdr if w not in self.mapper.mapping]:
                del self.last_hdr[wid]


# --- socket2 reader ----------------------------------------------------------

def socket2_path(env=os.environ):
    run = env.get("XDG_RUNTIME_DIR")
    sig = env.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not run or not sig:
        return None
    return os.path.join(run, "hypr", sig, ".socket2.sock")


def event_loop(bridge, path, stop, log=print_err):
    """Read socket2 lines forever; debounce refreshes; reconnect with backoff.
    Runs on its own thread. Any failure just retries: the port keeps working
    on incoming messages alone."""
    backoff = 1.0
    timer = None
    while not stop.is_set():
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(path)
                backoff = 1.0
                f = s.makefile("r", encoding="utf-8", errors="replace")
                for line in f:
                    if stop.is_set():
                        return
                    bridge.on_event(line.rstrip("\n"))
                    if bridge.pending_refresh:
                        if timer:
                            timer.cancel()
                        timer = threading.Timer(DEBOUNCE_S, bridge.flush)
                        timer.daemon = True
                        timer.start()
        except OSError as e:
            log(f"socket2 {path}: {e}; retrying in {backoff:.0f}s")
        stop.wait(backoff)
        backoff = min(backoff * 2, 30.0)


# --- dispatcher fragments (verified table forms, numeric prop values) -------

def lua_tag(address, tag):
    return f'hl.dispatch(hl.dsp.window.tag({{tag="{tag}", window="address:{address}"}}))'


def lua_prop(address, prop, value):
    return f'hl.dispatch(hl.dsp.window.set_prop({{prop="{prop}", value={value}, window="address:{address}"}}))'


def strip_calls(address, on):
    op = "+" if on else "-"
    v = 1 if on else 0
    return [
        lua_tag(address, f"{op}hyprglass_disabled"),
        lua_prop(address, "no_blur", v),
        lua_prop(address, "no_dim", v),
    ]


def undim_calls(address, on):
    return [lua_prop(address, "no_dim", 1 if on else 0)]


def rect_tags(rects, client, outer):
    """CSS px rects -> compositor-logical tag strings.

    Calibration: the extension sends the toplevel's outerWidth/Height in CSS
    px; the compositor reports the same window's logical size, so the ratio
    converts without knowing the monitor scale or Firefox's devPixelsPerPx.
    """
    sx = sy = 1.0
    try:
        size = client.get("size") or []
        if outer and outer.get("w") and outer.get("h") and len(size) == 2:
            sx = float(size[0]) / float(outer["w"])
            sy = float(size[1]) / float(outer["h"])
            if not (0.25 <= sx <= 4.0 and 0.25 <= sy <= 4.0):
                sx = sy = 1.0
    except (TypeError, ValueError, ZeroDivisionError):
        sx = sy = 1.0
    tags = set()
    for r in rects or []:
        try:
            x = int(round(float(r["x"]) * sx))
            y = int(round(float(r["y"]) * sy))
            w = int(round(float(r["w"]) * sx))
            h = int(round(float(r["h"]) * sy))
        except (KeyError, TypeError, ValueError):
            continue
        if w <= 0 or h <= 0:
            continue
        tags.add(f"{RECT_PREFIX}{x},{y},{w},{h}")
    return tags


class Applied:
    """What this host has put on one window, so it can be diffed and undone."""

    def __init__(self):
        self.mode = None       # "strip" | "undim" | None
        self.rects = set()     # rect tag strings currently on the window
        self.rect_dim = False  # no_dim held because rects are present


def apply_state(address, client, playing, rects, outer, cfg, applied, run=hyprctl):
    action = cfg.get("playbackAction", "rect")
    calls = []

    if action == "rect":
        want = rect_tags(rects, client, outer) if playing else set()
        # Rect tags: remove stale, add new. Never clear_tags: that would also
        # drop the rule-applied hyprglass_masked tag.
        for t in sorted(applied.rects - want):
            calls.append(lua_tag(address, f"-{t}"))
        for t in sorted(want - applied.rects):
            calls.append(lua_tag(address, f"+{t}"))
        applied.rects = want

        want_mode = None
        if playing and not want:
            fb = cfg.get("rectFallback", "none")
            want_mode = fb if fb in ("strip", "undim") else None
    else:
        want_mode = action if playing else None
        if applied.rects:
            for t in sorted(applied.rects):
                calls.append(lua_tag(address, f"-{t}"))
            applied.rects = set()

    # Whole-window mode transitions (strip/undim, or the rect fallback).
    if applied.mode != want_mode:
        if applied.mode == "strip":
            calls += strip_calls(address, False)
        elif applied.mode == "undim":
            calls += undim_calls(address, False)
        if want_mode == "strip":
            calls += strip_calls(address, True)
        elif want_mode == "undim":
            calls += undim_calls(address, True)
        applied.mode = want_mode

    # no_dim rides with rect presence; the plugin overlay owns dim meanwhile.
    # Only touch it when no whole-window mode already holds it.
    want_rect_dim = bool(applied.rects)
    if applied.rect_dim != want_rect_dim:
        if applied.mode is None:
            calls += undim_calls(address, want_rect_dim)
        applied.rect_dim = want_rect_dim

    if calls:
        run("eval", "\n".join(calls))


def clear_all(applied_by_addr):
    """Host exit: best-effort undo so a Firefox quit strands nothing."""
    cfg = {"playbackAction": "rect", "rectFallback": "none"}
    for address, applied in applied_by_addr.items():
        try:
            apply_state(address, {}, False, [], None, cfg, applied)
        except Exception:
            pass


def main():
    cfg = load_config()
    # One config file, host-distributed: the extension gets its half on connect.
    send_message(
        {
            "type": "config",
            "playbackAction": cfg.get("playbackAction", DEFAULTS["playbackAction"]),
            "playSignal": cfg.get("playSignal", DEFAULTS["playSignal"]),
            "pauseGraceMs": cfg.get("pauseGraceMs", DEFAULTS["pauseGraceMs"]),
            "rectRateHz": cfg.get("rectRateHz", DEFAULTS["rectRateHz"]),
            "hdr": bool(cfg.get("hdrEnable", DEFAULTS["hdrEnable"])),
        }
    )
    state = HyprState()
    state.refresh_monitors()
    state.refresh_clients()
    trace("start", {"ppid": os.getppid(), "socket2": socket2_path(), "clients": len(state.clients),
                    "monitors": state.monitors})
    bridge = Bridge(state, Mapper(), send_message)

    stop = threading.Event()
    path = socket2_path()
    if path and os.path.exists(path):
        threading.Thread(target=event_loop, args=(bridge, path, stop), daemon=True).start()
    else:
        path = None
        print_err("no Hyprland socket2; HDR answers refresh only on extension messages")

    try:
        while True:
            msg = read_message()
            if msg is None:
                break
            if path is None:
                bridge.pending_refresh = True
                bridge.flush()
            bridge.on_message(msg)
    finally:
        stop.set()
        clear_all(bridge.applied)


if __name__ == "__main__":
    main()
