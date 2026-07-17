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

All state and hyprctl dispatch live in scratchpad_cycle.py; this daemon only
translates events into `scratchpad-cycle float-fix <addr>` calls. socket2 emits
addresses WITHOUT the 0x prefix; the subcommand normalizes. The socket2 glue
(find_instance/connect_socket2/parse_event) is imported from hypr_ipc; the pure
decision (classify) is covered by hypr_scratchpad_guard_test.py.
"""
from __future__ import annotations

import subprocess
import sys
import time

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
# Hyprland I/O (socket2 glue shared via hypr_ipc)
# ---------------------------------------------------------------------------
def dispatch_action(cycle_script, action, addr):
    """Shell out to scratchpad-cycle to mutate pad state / fix floating."""
    subprocess.run(["python3", cycle_script, action, addr],
                   capture_output=True, check=False)


def run(cycle_script):
    """Main loop: connect to socket2, classify each event, run the subcommand."""
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
        try:
            buf = b""
            while True:
                data = sock.recv(65536)
                if not data:  # Hyprland went away -> reconnect
                    break
                buf += data
                while b"\n" in buf:
                    raw, buf = buf.split(b"\n", 1)
                    name, payload = parse_event(raw.decode("utf-8", "ignore"))
                    action, addr = classify(name, payload)
                    if action and addr:
                        dispatch_action(cycle_script, action, addr)
        except OSError:
            pass
        finally:
            sock.close()
        time.sleep(0.5)


def main(argv):
    cycle_script = argv[1] if len(argv) > 1 else "scratchpad_cycle.py"
    run(cycle_script)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
