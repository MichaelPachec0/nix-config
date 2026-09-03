#!/usr/bin/env python3
"""Native-messaging host for ff-hyprglass-bridge.

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

Every failure degrades to doing nothing: the compositor keeps R2 mask-mode
behaviour, which is already visually correct without this bridge.
"""
import json
import os
import struct
import subprocess
import sys

CONFIG_PATH = os.path.expanduser("~/.config/ff-hyprglass-bridge.json")
RECT_PREFIX = "hyprglass_rect:"

DEFAULTS = {
    "playbackAction": "rect",
    "playSignal": "activeTab",
    "pauseGraceMs": 3000,
    "rectFallback": "none",
    "rectRateHz": 10,
}


def load_config():
    cfg = dict(DEFAULTS)
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            cfg.update(json.load(f))
    except (OSError, ValueError):
        pass
    return cfg


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
        return json.loads(data)
    except ValueError:
        return None


def send_message(obj):
    data = json.dumps(obj).encode()
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


def find_window(title):
    """Correlate the extension's window title with a Hyprland client record.

    Firefox toplevel titles carry the page title, so exact match first; fall
    back to the focused firefox window, then to the sole firefox window.
    A miss returns None and the caller does nothing (degrade stance).
    """
    try:
        clients = json.loads(hyprctl("clients", "-j") or "[]")
    except ValueError:
        return None
    ff = [c for c in clients if str(c.get("class", "")).startswith("firefox")]
    if not ff:
        return None
    for c in ff:
        if c.get("title") == title:
            return c
    focused = [c for c in ff if c.get("focusHistoryID") == 0]
    if focused:
        return focused[0]
    if len(ff) == 1:
        return ff[0]
    return None


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


def apply_state(address, client, playing, rects, outer, cfg, applied):
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
        hyprctl("eval", "\n".join(calls))


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
        }
    )
    applied_by_addr = {}
    try:
        while True:
            msg = read_message()
            if msg is None:
                break
            if msg.get("type") != "state":
                continue
            cfg = load_config()  # cheap; picks up edits without restart
            client = find_window(str(msg.get("title", "")))
            if not client:
                continue
            address = client["address"]
            applied = applied_by_addr.setdefault(address, Applied())
            apply_state(
                address,
                client,
                bool(msg.get("playing")),
                msg.get("rects") or [],
                msg.get("outer"),
                cfg,
                applied,
            )
    finally:
        clear_all(applied_by_addr)


if __name__ == "__main__":
    main()
