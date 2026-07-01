#!/usr/bin/env python3
"""hypr-window-keeper: pin matched Hyprland windows to a configured position.

Some (usually Electron) apps drift their own floating window on resize -- e.g.
Windscribe shoves its window up when the Locations panel expands and never
restores it. Hyprland has no "keep centered" rule, and app-driven resizes emit
no socket2 event, so nothing can passively correct it. This daemon watches the
event socket (socket2) for create / move / title / float-mode changes AND polls
lightly while a matched window exists (to catch the eventless resize), then
re-applies each window's target position via `hl.dsp.window.move`.

Config is a JSON file (generated from Nix) passed as argv[1]:

    { "rules": [
        { "match": { "title": "^Windscribe$" }, "position": "center" },
        { "match": { "class": "^Foo$" },  "position": { "anchor": "top-right", "margin": 12 } },
        { "match": { "title": "Bar" },     "position": { "x": 100, "y": 60 } }
    ] }

`match` keys are any of class / title / initialClass / initialTitle; each value
is a regex (re.search), and ALL listed keys must match. `position` is
"center" | { x, y } (monitor-relative px) | { anchor, margin }. Only floating
windows are moved (tiled windows belong to the layout).

The pure helpers (parse_rules / matches / usable_area / compute_target) are
covered by hypr-window-keeper_test.py; the rest is I/O glue.
"""
from __future__ import annotations

import json
import os
import re
import select
import socket
import subprocess
import sys
import time

# Move only when off-target by more than this (px) -- avoids fighting the
# move animation with redundant commands.
TOLERANCE = 3
# Poll cadence (seconds) while a matched window exists, to catch app-driven
# resizes that emit no socket2 event.
POLL_INTERVAL = 0.4
# socket2 events that can change a window's identity, workspace or geometry
# and therefore warrant a reconcile. Anything else is ignored.
RELEVANT_EVENTS = frozenset({
    "openwindow", "openwindowv2",
    "closewindow",
    "movewindow", "movewindowv2",
    "windowtitle", "windowtitlev2",
    "changefloatingmode",
    "workspace", "workspacev2",
    "activewindow", "activewindowv2",
    "fullscreen",
})
MATCH_FIELDS = ("class", "title", "initialClass", "initialTitle")


# ---------------------------------------------------------------------------
# Pure helpers (unit-tested)
# ---------------------------------------------------------------------------
def normalize_position(pos):
    """Normalise a config `position` into {kind, ...}. Raises on invalid input."""
    if isinstance(pos, str):
        if pos == "center":
            return {"kind": "center"}
        raise ValueError(f"unknown position string: {pos!r}")
    if isinstance(pos, dict):
        if pos.get("anchor"):
            return {"kind": "anchor", "anchor": pos["anchor"], "margin": pos.get("margin", 0)}
        if pos.get("x") is not None and pos.get("y") is not None:
            return {"kind": "fixed", "x": pos["x"], "y": pos["y"]}
    raise ValueError(f"invalid position: {pos!r}")


def parse_rules(cfg):
    """Turn the parsed JSON config into a list of {match, pos} rules."""
    rules = []
    for raw in cfg.get("rules", []):
        rules.append({"match": raw["match"], "pos": normalize_position(raw["position"])})
    return rules


def matches(match, win):
    """True if every field regex in `match` search-matches the window's field."""
    for key, pattern in match.items():
        if re.search(pattern, win.get(key) or "") is None:
            return False
    return True


def usable_area(mon):
    """Logical (scaled) usable rectangle of a monitor, minus reserved bars.

    hyprctl monitors reports physical width/height and reserved as
    [left, top, right, bottom] in logical px; window at/size are logical.
    Returns (x, y, w, h).
    """
    scale = mon.get("scale") or 1
    w = mon["width"] / scale
    h = mon["height"] / scale
    left, top, right, bottom = (mon.get("reserved") or [0, 0, 0, 0])
    return (mon["x"] + left, mon["y"] + top, w - left - right, h - top - bottom)


def compute_target(pos, size, mon):
    """Target (x, y) for a window of `size` under position spec `pos` on `mon`."""
    ux, uy, uw, uh = usable_area(mon)
    ww, wh = size

    if pos["kind"] == "center":
        return (round(ux + (uw - ww) / 2), round(uy + (uh - wh) / 2))

    if pos["kind"] == "fixed":
        return (round(mon["x"] + pos["x"]), round(mon["y"] + pos["y"]))

    if pos["kind"] == "anchor":
        anchor = pos["anchor"]
        margin = pos.get("margin", 0)
        if anchor in ("left", "top-left", "bottom-left"):
            x = ux + margin
        elif anchor in ("right", "top-right", "bottom-right"):
            x = ux + uw - ww - margin
        else:  # center / top / bottom -> horizontally centered
            x = ux + (uw - ww) / 2
        if anchor in ("top", "top-left", "top-right"):
            y = uy + margin
        elif anchor in ("bottom", "bottom-left", "bottom-right"):
            y = uy + uh - wh - margin
        else:  # center / left / right -> vertically centered
            y = uy + (uh - wh) / 2
        return (round(x), round(y))

    raise ValueError(f"unknown position kind: {pos['kind']!r}")


# ---------------------------------------------------------------------------
# Hyprland I/O
# ---------------------------------------------------------------------------
def find_instance():
    """(signature, socket2_path) for the running Hyprland, or (None, None)."""
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    base = os.path.join(runtime, "hypr")
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if sig and os.path.exists(os.path.join(base, sig, ".socket2.sock")):
        return sig, os.path.join(base, sig, ".socket2.sock")
    if not os.path.isdir(base):
        return None, None
    found = []
    for name in os.listdir(base):
        sock = os.path.join(base, name, ".socket2.sock")
        if os.path.exists(sock):
            found.append((os.path.getmtime(os.path.join(base, name)), name, sock))
    if not found:
        return None, None
    found.sort()
    return found[-1][1], found[-1][2]


def hyprctl_json(sig, *args):
    env = {**os.environ, "HYPRLAND_INSTANCE_SIGNATURE": sig}
    out = subprocess.run(
        ["hyprctl", *args, "-j"], capture_output=True, text=True, env=env, check=False
    )
    return json.loads(out.stdout or "[]")


def hyprctl(sig, *args):
    env = {**os.environ, "HYPRLAND_INSTANCE_SIGNATURE": sig}
    subprocess.run(["hyprctl", *args], capture_output=True, env=env, check=False)


def reconcile(sig, rules):
    """Move every matched, off-target floating window to its target.

    Returns True if at least one matched window is currently present (so the
    caller knows to keep polling).
    """
    try:
        clients = hyprctl_json(sig, "clients")
        monitors = {m["id"]: m for m in hyprctl_json(sig, "monitors")}
    except (json.JSONDecodeError, KeyError):
        return False

    present = False
    for win in clients:
        if not win.get("floating"):
            continue
        for rule in rules:
            if not matches(rule["match"], win):
                continue
            present = True
            mon = monitors.get(win.get("monitor"))
            if mon is None:
                break
            tx, ty = compute_target(rule["pos"], win["size"], mon)
            cx, cy = win["at"]
            if abs(cx - tx) > TOLERANCE or abs(cy - ty) > TOLERANCE:
                # Lua config manager: `hyprctl dispatch` wraps its arg in
                # hl.dispatch(...), so pass a Lua dispatcher expression.
                # window = "address:..." targets this window without focusing it.
                hyprctl(sig, "dispatch",
                        f'hl.dsp.window.move({{ x = {tx}, y = {ty}, '
                        f'window = "address:{win["address"]}" }})')
            break  # first matching rule wins
    return present


def connect_socket2(path):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(path)
    return sock


def run(rules):
    """Main loop: reconnect to Hyprland, react to events, poll while present."""
    while True:
        sig, sock_path = find_instance()
        if not sig:
            time.sleep(1.0)
            continue
        try:
            sock = connect_socket2(sock_path)
        except OSError:
            time.sleep(1.0)
            continue

        present = reconcile(sig, rules)
        try:
            while True:
                timeout = POLL_INTERVAL if present else None
                readable, _, _ = select.select([sock], [], [], timeout)
                if readable:
                    data = sock.recv(65536)
                    if not data:  # Hyprland went away -> reconnect
                        break
                    events = data.decode("utf-8", "ignore").splitlines()
                    if any(ev.split(">>", 1)[0] in RELEVANT_EVENTS for ev in events):
                        present = reconcile(sig, rules)
                else:  # poll tick
                    present = reconcile(sig, rules)
        except OSError:
            pass
        finally:
            sock.close()
        time.sleep(0.5)


def main(argv):
    if len(argv) < 2:
        print("usage: hypr-window-keeper <config.json>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as fh:
        cfg = json.load(fh)
    rules = parse_rules(cfg)
    if not rules:
        print("hypr-window-keeper: no rules configured, exiting", file=sys.stderr)
        return 0
    run(rules)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
