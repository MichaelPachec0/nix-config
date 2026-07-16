#!/usr/bin/env python3
"""hypr-monitor-arrange: re-arrange layer surfaces after a monitor is removed.

When an external monitor is unplugged, Hyprland core migrates the removed
monitor's layer-shell surfaces (wallpaper, bar, notification popups) onto a
surviving monitor's layer list but skips `arrangeLayersForMonitor` for the
target, so they keep the dead monitor's global origin and render off-screen.
The surfaces are never destroyed -- only mis-positioned -- so `hyprctl reload`
(which re-applies the monitor rules and runs the missing arrange pass) snaps
them back. hy3 is not involved: it lays out tiled windows, not layer surfaces.

This daemon watches the event socket (socket2) and, on a `monitorremoved`
event, runs `hyprctl reload` after a short debounce (so undocking several
outputs at once coalesces into a single reload). `hyprctl reload` is a
subcommand, so it works under the Lua config parser (unlike `hyprctl dispatch`
/ `keyword`, which the non-legacy parser rejects).

The socket2 discovery / reconnect glue (find_instance / connect_socket2 /
parse_event) now lives in the shared hypr_ipc module. The local pure helpers
(is_trigger_event / Debouncer) are covered by hypr_monitor_arrange_test.py; the
rest is I/O glue.
"""
from __future__ import annotations

import os
import select
import subprocess
import sys
import time

from hypr_ipc import connect_socket2, find_instance, parse_event

# Coalesce a burst of monitor removals (e.g. undocking a multi-head dock) into a
# single reload: fire only after this many ms of quiet.
DEBOUNCE_MS = 600
# socket2 event name prefix that warrants a re-arrange. Removal-only by design;
# monitor *adds* are arranged correctly by Hyprland already. Prefix-match so a
# hypothetical `monitorremovedv2` is covered too.
TRIGGER_PREFIX = "monitorremoved"


# ---------------------------------------------------------------------------
# Pure helpers (unit-tested)
# ---------------------------------------------------------------------------
def is_trigger_event(name):
    """True for the monitor-removed event(s) that warrant a re-arrange."""
    return name.startswith(TRIGGER_PREFIX)


class Debouncer:
    """Coalesce repeated triggers into one deferred fire.

    Clock is injected (a zero-arg callable returning a monotonic float) so the
    timing is deterministic under test -- no sleeps.
    """

    def __init__(self, delay_s, now_fn):
        self._delay = delay_s
        self._now = now_fn
        self._fire_at = None

    def arm(self):
        """(Re)start the timer -- fire `delay_s` after the most recent call."""
        self._fire_at = self._now() + self._delay

    def pending(self):
        return self._fire_at is not None

    def time_until(self):
        """Seconds until fire (>=0), or None when idle. Use as a select timeout."""
        if self._fire_at is None:
            return None
        return max(0.0, self._fire_at - self._now())

    def due(self):
        """True once armed and the quiet window has elapsed."""
        return self._fire_at is not None and self._now() >= self._fire_at

    def clear(self):
        self._fire_at = None


# ---------------------------------------------------------------------------
# Hyprland I/O (shared shape with hypr_window_keeper.py)
# ---------------------------------------------------------------------------
def hyprctl(sig, *args):
    env = {**os.environ, "HYPRLAND_INSTANCE_SIGNATURE": sig}
    subprocess.run(["hyprctl", *args], capture_output=True, env=env, check=False)


def run(delay_s):
    """Main loop: reconnect to Hyprland, debounce monitorremoved, then reload."""
    debouncer = Debouncer(delay_s, time.monotonic)
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

        debouncer.clear()
        try:
            while True:
                readable, _, _ = select.select([sock], [], [], debouncer.time_until())
                if readable:
                    data = sock.recv(65536)
                    if not data:  # Hyprland went away -> reconnect
                        break
                    for line in data.decode("utf-8", "ignore").splitlines():
                        name, _ = parse_event(line)
                        if is_trigger_event(name):
                            debouncer.arm()
                if debouncer.due():
                    debouncer.clear()
                    hyprctl(sig, "reload")
        except OSError:
            pass
        finally:
            sock.close()
        time.sleep(0.5)


def main(argv):
    run(DEBOUNCE_MS / 1000.0)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
