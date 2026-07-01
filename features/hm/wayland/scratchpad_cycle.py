#!/usr/bin/env python3
"""scratchpad-cycle: sway-style cycling scratchpad for Hyprland.

The scratchpad is the special workspace "magic". Windows parked there are the
hidden pool. Each `cycle` reveals the *next* pool member on the active
workspace and hides the previously-shown one -- one at a time -- like sway's
`scratchpad show`. The rotation includes an empty step: after the last member
comes "nothing shown" (all hidden), then it wraps back to the first. A single
member toggles (show, then hide). `reset` (Super+Ctrl+-) sends every member
currently pulled out straight back to the scratchpad, using a tracked
membership set so it catches all of them -- not just the last one shown -- and
notifies so the keypress is always observable.

Two runtime files hold state: which member is currently pulled out (a shown
window is no longer in the special workspace to be re-derived from), and the
full membership set (so `reset` can find every out member).

Hyprland runs the Lua config manager, so `hyprctl dispatch` takes a Lua
dispatcher expression, not the old string form:
  hl.dsp.window.move({ workspace = "...", window = "address:0x..." })
Moving INTO the special workspace needs `follow = false` (the silent move,
movetoworkspacesilent); the default follows the window and surfaces the special
pane on the monitor, so the "hidden" window stays on screen.

The pure decisions (`plan`, `update_members`) are covered by
scratchpad_cycle_test.py; the rest is Hyprland I/O.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

SPECIAL = "magic"
SPECIAL_WS = f"special:{SPECIAL}"
_RT = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
# Which member (if any) is currently pulled out onto a normal workspace.
STATE_FILE = os.path.join(_RT, "hypr-scratchpad-shown")
# The full membership set: every window that has been in the pad. Lets `reset`
# find members that are currently OUT even when the single state pointer above
# doesn't track them (multiple out, stale pointer, etc.).
MEMBERS_FILE = os.path.join(_RT, "hypr-scratchpad-members")


# ---------------------------------------------------------------------------
# Pure rotation logic (unit-tested)
# ---------------------------------------------------------------------------
def plan(hidden, shown):
    """Decide the next scratchpad action.

    hidden : addresses currently parked in the special workspace.
    shown  : address currently pulled out onto a normal workspace, or None.

    Returns (to_hide, to_show, new_state):
      to_hide   -- address to send back to the special workspace, or None
      to_show   -- address to reveal on the active workspace, or None
      new_state -- address to record as the shown one, or None

    The sequence is None -> members[0] -> ... -> members[-1] -> None -> ...:
    an empty (all-hidden) step sits after the last member before wrapping.
    """
    members = sorted(set(hidden) | ({shown} if shown else set()))
    if not members:
        return (None, None, None)
    if shown is None:
        return (None, members[0], members[0])
    idx = members.index(shown)
    if idx == len(members) - 1:  # past the last member -> empty (hide all)
        return (shown, None, None)
    nxt = members[idx + 1]
    return (shown, nxt, nxt)


def update_members(existing, hidden, shown, live):
    """Refresh the membership set: union prior members with what's in the pad
    now (hidden) plus the pulled-out one (shown), pruned to still-open windows.

    existing : addresses previously recorded as members.
    hidden   : addresses currently parked in the special workspace.
    shown    : address currently pulled out, or None.
    live     : addresses of all currently-open windows (for pruning).
    """
    members = set(existing) | set(hidden) | ({shown} if shown else set())
    return sorted(members & set(live))


# ---------------------------------------------------------------------------
# Hyprland I/O
# ---------------------------------------------------------------------------
def hyprctl_json(*args):
    out = subprocess.run(["hyprctl", *args, "-j"], capture_output=True, text=True, check=False)
    return json.loads(out.stdout or "null")


def dispatch(expr):
    subprocess.run(["hyprctl", "dispatch", expr], capture_output=True, check=False)


def notify(msg):
    try:
        subprocess.run(["notify-send", "-t", "1500", "Scratchpad", msg],
                       capture_output=True, check=False)
    except FileNotFoundError:
        pass


def read_state():
    try:
        with open(STATE_FILE, encoding="utf-8") as fh:
            return fh.read().strip() or None
    except OSError:
        return None


def write_state(addr):
    with open(STATE_FILE, "w", encoding="utf-8") as fh:
        fh.write(addr or "")


def read_members():
    try:
        with open(MEMBERS_FILE, encoding="utf-8") as fh:
            return [line.strip() for line in fh if line.strip()]
    except OSError:
        return []


def write_members(addrs):
    with open(MEMBERS_FILE, "w", encoding="utf-8") as fh:
        fh.write("\n".join(sorted(set(addrs))))


def workspace_name(win):
    return (win.get("workspace") or {}).get("name")


def cycle():
    clients = hyprctl_json("clients") or []
    by_addr = {c["address"]: c for c in clients}

    hidden = [c["address"] for c in clients if workspace_name(c) == SPECIAL_WS]

    shown = read_state()
    # Drop a stale pointer: window closed, or already back in the special ws.
    if shown and (shown not in by_addr or workspace_name(by_addr[shown]) == SPECIAL_WS):
        shown = None

    # Keep the membership set fresh so `reset` can find every out member.
    write_members(update_members(read_members(), hidden, shown, by_addr))

    to_hide, to_show, new_state = plan(hidden, shown)

    if to_hide is None and to_show is None and new_state is None and not hidden and not shown:
        notify("empty")
        write_state(None)
        return

    if to_hide:
        # follow = false -> silent move (movetoworkspacesilent). Without it the
        # move FOLLOWS the window and surfaces the special pane on the monitor,
        # leaving the "hidden" window on screen.
        dispatch(f'hl.dsp.window.move({{ workspace = "{SPECIAL_WS}", '
                 f'follow = false, window = "address:{to_hide}" }})')
    if to_show:
        ws = str((hyprctl_json("activeworkspace") or {}).get("id"))
        dispatch(f'hl.dsp.window.move({{ workspace = "{ws}", window = "address:{to_show}" }})')
        dispatch(f'hl.dsp.focus({{ window = "address:{to_show}" }})')

    write_state(new_state)


def reset():
    """Send EVERY scratchpad member that's currently out back to special:magic.

    "Out" = a member window on a normal workspace. Members come from the tracked
    set (MEMBERS_FILE) unioned with the state pointer, so this catches every
    pulled-out window, not just the last one the cycle showed. Returns to the
    fully-hidden state regardless of where the rotation was. Bound to Super+Ctrl+-.
    Notifies so the keypress is observable even when there's nothing to do.
    """
    clients = hyprctl_json("clients") or []
    by_addr = {c["address"]: c for c in clients}

    shown = read_state()
    candidates = set(read_members())
    if shown:
        candidates.add(shown)

    out = [a for a in candidates
           if a in by_addr and workspace_name(by_addr[a]) != SPECIAL_WS]
    for addr in sorted(out):
        # follow = false -> silent move; otherwise the special pane surfaces and
        # the window stays visible instead of being stashed out of sight.
        dispatch(f'hl.dsp.window.move({{ workspace = "{SPECIAL_WS}", '
                 f'follow = false, window = "address:{addr}" }})')

    # Prune closed windows from the tracked set; nothing is pulled out now.
    write_members(a for a in candidates if a in by_addr)
    write_state(None)
    notify(f"stashed {len(out)}" if out else "nothing out")


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "cycle"
    if cmd == "reset":
        reset()
    else:
        cycle()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
