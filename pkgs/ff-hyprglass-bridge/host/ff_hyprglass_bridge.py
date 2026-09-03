#!/usr/bin/env python3
"""Native-messaging host for ff-hyprglass-bridge.

Receives per-window playback state from the WebExtension and applies or
clears Hyprland window tags/props through `hyprctl eval` (the Lua config
manager rejects `hyprctl dispatch`, so eval is the only runtime entry).

Every failure degrades to doing nothing: the compositor keeps R2 mask-mode
behaviour, which is already visually correct without this bridge.
"""
import json
import os
import struct
import subprocess
import sys

CONFIG_PATH = os.path.expanduser("~/.config/ff-hyprglass-bridge.json")

def load_config():
    cfg = {"playbackAction": "strip", "playSignal": "activeTab", "pauseGraceMs": 3000}
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
    """Correlate the extension's window title with a Hyprland client address.

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
            return c["address"]
    focused = [c for c in ff if c.get("focusHistoryID") == 0]
    if focused:
        return focused[0]["address"]
    if len(ff) == 1:
        return ff[0]["address"]
    return None

def apply_state(address, playing, action):
    tag_op = "+" if playing else "-"
    value = 1 if playing else 0
    calls = [
        f'hl.dispatch(hl.dsp.window.set_prop({{prop="no_dim", value={value}, window="address:{address}"}}))'
    ]
    if action == "strip":
        calls.insert(
            0,
            f'hl.dispatch(hl.dsp.window.tag({{tag="{tag_op}hyprglass_disabled", window="address:{address}"}}))',
        )
        calls.insert(
            1,
            f'hl.dispatch(hl.dsp.window.set_prop({{prop="no_blur", value={value}, window="address:{address}"}}))',
        )
    hyprctl("eval", "\n".join(calls))

def main():
    cfg = load_config()
    # One config file, host-distributed: the extension gets its half on connect.
    send_message(
        {
            "type": "config",
            "playSignal": cfg.get("playSignal", "activeTab"),
            "pauseGraceMs": cfg.get("pauseGraceMs", 3000),
        }
    )
    # address -> True while stripped, so host exit knowledge stays local;
    # a dead host simply stops updating (degrade stance).
    applied = {}
    while True:
        msg = read_message()
        if msg is None:
            break
        if msg.get("type") != "state":
            continue
        cfg = load_config()  # cheap; picks up edits without restart
        address = find_window(str(msg.get("title", "")))
        if not address:
            continue
        playing = bool(msg.get("playing"))
        if applied.get(address) == playing:
            continue
        applied[address] = playing
        apply_state(address, playing, cfg.get("playbackAction", "strip"))

if __name__ == "__main__":
    main()
