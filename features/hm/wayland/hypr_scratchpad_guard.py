#!/usr/bin/env python3
"""hypr-scratchpad-guard: keep the Hyprland scratchpad (special:magic) float-only.

Two behaviors, both driven by the Hyprland event socket (socket2):

  * Eviction -- when a scratchpad member's floating attribute is turned OFF
    (changefloatingmode>>ADDR,0), the member is removed from the pad. sway-style:
    a tiled window does not belong in the scratchpad.
  * Self-heal -- when a *tiled* window is moved into special:magic
    (movewindowv2>>ADDR,WSID,special:magic), it is floated in place, so the pad
    can never hold a tiled window (which strands it hidden).

`openwindow` is intentionally NOT watched: a rule-parked app (keepassxc,
windscribe) fires openwindow before its float=true rule is guaranteed applied,
so a float-fix in that gap could toggle a correctly-floating window tiled.

All state and hyprctl dispatch live in scratchpad_cycle.py; this daemon only
translates events into `scratchpad-cycle evict <addr>` / `float-fix <addr>`
calls. socket2 emits addresses WITHOUT the 0x prefix; the subcommands normalize.
The socket2 glue (find_instance/connect_socket2/parse_event) is imported from
hypr_ipc; the pure decision (classify) is covered by hypr_scratchpad_guard_test.py.
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

      changefloatingmode>>ADDR,FLOATING  -> ("evict", ADDR)      if FLOATING == "0"
      movewindowv2>>ADDR,WSID,WSNAME     -> ("float-fix", ADDR)  if WSNAME == special:magic

    addr is returned verbatim (no 0x prefix, as socket2 emits it); the
    scratchpad-cycle subcommands normalize it.
    """
    if name == "changefloatingmode":
        parts = data.split(",")
        if len(parts) >= 2 and parts[1].strip() == "0":
            return ("evict", parts[0])
        return (None, None)
    if name == "movewindowv2":
        # ADDR,WSID,WSNAME -- WSNAME is the remainder (may itself contain commas).
        parts = data.split(",", 2)
        if len(parts) == 3 and parts[2] == SPECIAL_WS:
            return ("float-fix", parts[0])
        return (None, None)
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
