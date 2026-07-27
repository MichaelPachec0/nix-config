#!/usr/bin/env python3
"""hypr_ipc: shared Hyprland event-socket (socket2) helpers.

Small glue reused by the socket2-listener daemons (hypr_monitor_arrange,
hypr_window_keeper, hypr_scratchpad_guard): locate the running Hyprland
instance, connect to its event socket, and split an event line. Kept as one
importable module (co-located on PYTHONPATH by each daemon's Nix packaging, via
hypr-ipc-py.nix) so the daemons share a single copy. parse_event is pure and
covered by hypr_ipc_test.py; find_instance / connect_socket2 / request /
request_json are filesystem / socket I/O. request talks to the *request* socket
(.socket.sock) so daemons can query and dispatch without spawning hyprctl
(a direct round-trip is ~0.1ms; forking the hyprctl binary is ~12ms).
"""
from __future__ import annotations

import json
import os
import socket


def parse_event(line):
    """Split a socket2 line `EVENT>>DATA` into (name, data). data may be ''."""
    name, sep, data = line.partition(">>")
    return name, data if sep else ""


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


def connect_socket2(path):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(path)
    return sock


def request(sig, cmd):
    """Send one command to Hyprland's request socket (.socket.sock) and return
    the reply text. `cmd` is the raw wire form hyprctl would send, e.g.
    "dispatch <expr>", "reload", or "j/clients" for JSON output. A direct
    round-trip is ~0.1ms; spawning `hyprctl` is ~12ms (fork/exec of the binary).
    Returns "" on connection error, matching the daemons' old fire-and-forget
    `check=False` behaviour."""
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    path = os.path.join(runtime, "hypr", sig, ".socket.sock")
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.connect(path)
            sock.sendall(cmd.encode("utf-8"))
            buf = bytearray()
            while chunk := sock.recv(65536):
                buf.extend(chunk)
        return buf.decode("utf-8", "replace")
    except OSError:
        return ""


def request_json(sig, name):
    """request() a JSON command (the name without the 'j/' prefix) and parse the
    reply. Returns the parsed object, or None on an empty / malformed reply."""
    text = request(sig, "j/" + name)
    try:
        return json.loads(text) if text else None
    except json.JSONDecodeError:
        return None
