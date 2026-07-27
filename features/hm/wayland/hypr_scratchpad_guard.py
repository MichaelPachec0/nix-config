#!/usr/bin/env python3
"""hypr-scratchpad-guard: self-heal the Hyprland scratchpad (special:magic) float-only.

When a *tiled* window is moved into special:magic
(movewindowv2>>ADDR,WSID,special:magic) it is floated in place, so the pad can
never hold a tiled window (which strands it hidden). This covers windows that
reach the pad by any move path -- window rules, manual `movetoworkspace`, etc.

Eviction (dropping a member that gets un-floated) is NOT handled here: Hyprland
0.55.4 emits NO socket2 event on a float-state change (verified -- toggling
floating produces zero events), so an un-float is invisible to this daemon.
Eviction is driven from the float-toggle keybind instead: Super+Shift+f runs
`scratchpad-cycle toggle-float`, which toggles floating and evicts a member that
became tiled.

`openwindow` is intentionally NOT watched: a rule-parked app (keepassxc,
windscribe) fires openwindow before its float=true rule is guaranteed applied,
so a float-fix in that gap could toggle a correctly-floating window tiled.

This is the resident scratchpad daemon: it services BOTH the event socket
(self-heal float-fix, above) AND a command FIFO (scratchpad_cycle.CMD_FIFO) that
the keybinds write to, running every action in-process via
scratchpad_cycle.run_command -- so a keypress or event never spawns a fresh
python. All pad state and hyprctl dispatch live in scratchpad_cycle.py. socket2
emits addresses WITHOUT the 0x prefix; run_command normalizes. The socket2 glue
(find_instance/connect_socket2/parse_event) is imported from hypr_ipc; the pure
bits (classify, run_line parsing) are covered by hypr_scratchpad_guard_test.py.
"""
from __future__ import annotations

import os
import select
import stat
import sys

import scratchpad_cycle
from hypr_ipc import connect_socket2, find_instance, parse_event

SPECIAL_WS = "special:magic"


# ---------------------------------------------------------------------------
# Pure decision (unit-tested)
# ---------------------------------------------------------------------------
def classify(name, data):
    """Map a socket2 event to (action, addr), or (None, None) when irrelevant.

      movewindowv2>>ADDR,WSID,WSNAME  -> ("float-fix", ADDR)  if WSNAME == special:magic

    Only moves INTO the pad are watched (self-heal). Float-state changes are not:
    Hyprland emits no socket2 event for them, so eviction is keybind-driven (see
    the module docstring). addr is returned verbatim (no 0x prefix, as socket2
    emits it); the scratchpad-cycle subcommand normalizes it.
    """
    if name == "movewindowv2":
        # ADDR,WSID,WSNAME -- WSNAME is the remainder (may itself contain commas).
        parts = data.split(",", 2)
        if len(parts) == 3 and parts[2] == SPECIAL_WS:
            return ("float-fix", parts[0])
    return (None, None)


# ---------------------------------------------------------------------------
# Hyprland I/O + command FIFO (resident: no per-action python spawn)
# ---------------------------------------------------------------------------
def open_fifo(path):
    """Create (if needed) and open the command FIFO for reading. O_RDWR keeps it
    open with no EOF as keybind writers come and go; a stale non-FIFO is replaced."""
    if os.path.exists(path) and not stat.S_ISFIFO(os.stat(path).st_mode):
        os.unlink(path)
    try:
        os.mkfifo(path, 0o600)
    except FileExistsError:
        pass
    return os.open(path, os.O_RDWR)


def run_action(cmd, arg=None):
    """Run one scratchpad command in-process. A single bad command must never
    take down the resident daemon."""
    try:
        scratchpad_cycle.run_command(cmd, arg)
    except Exception:
        pass


def run_line(line):
    """Parse a FIFO command line ('cmd [arg]') and run it. Blank -> no-op."""
    parts = line.split()
    if parts:
        run_action(parts[0], parts[1] if len(parts) > 1 else None)


def run():
    """Resident loop: service the command FIFO (keybind actions) and the Hyprland
    event socket (self-heal float-fix) from one process, dispatching in-process.
    The FIFO is serviced even while the event socket is reconnecting."""
    fifo_fd = open_fifo(scratchpad_cycle.CMD_FIFO)
    sock = None
    sockbuf = b""
    fifobuf = b""
    while True:
        if sock is None:
            sig, sock_path = find_instance()
            if sig:
                try:
                    sock = connect_socket2(sock_path)
                    sockbuf = b""
                except OSError:
                    sock = None
        rlist = [fifo_fd] + ([sock] if sock is not None else [])
        try:
            readable, _, _ = select.select(rlist, [], [], 1.0)
        except OSError:
            readable = []
        if sock is not None and sock in readable:
            try:
                data = sock.recv(65536)
            except OSError:
                data = b""
            if not data:  # Hyprland went away -> drop and reconnect
                sock.close()
                sock = None
                sockbuf = b""
            else:
                sockbuf += data
                while b"\n" in sockbuf:
                    raw, sockbuf = sockbuf.split(b"\n", 1)
                    name, payload = parse_event(raw.decode("utf-8", "ignore"))
                    action, addr = classify(name, payload)
                    if action and addr:
                        run_action(action, addr)
        if fifo_fd in readable:
            fifobuf += os.read(fifo_fd, 65536)
            while b"\n" in fifobuf:
                line, fifobuf = fifobuf.split(b"\n", 1)
                run_line(line.decode("utf-8", "ignore"))


def main(argv):
    run()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
