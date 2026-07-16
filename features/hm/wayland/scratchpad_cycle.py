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

import datetime
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
# Debug trace: append-only, timestamped log of every cycle/reset decision. Off by
# default; enable with SCRATCHPAD_DEBUG=1 (any non-"0" value), then follow it with:
#   tail -f "$XDG_RUNTIME_DIR/hypr-scratchpad.log"
LOG_FILE = os.path.join(_RT, "hypr-scratchpad.log")
LOG_ENABLED = os.environ.get("SCRATCHPAD_DEBUG", "0") != "0"


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


def normalize_addr(addr):
    """Return addr as a lowercase 0x-prefixed hex string.

    socket2 events emit window addresses without the 0x prefix
    (`593cb426c700`); `hyprctl clients` uses `0x593cb426c700`. Reconcile the two
    so membership comparisons match. None / empty / whitespace -> None.
    """
    if not addr:
        return None
    a = addr.strip().lower()
    if not a:
        return None
    return a if a.startswith("0x") else "0x" + a


def forget(addr, members, shown):
    """Pure decision for dropping a window from the pad.

    Returns (new_members, clear_shown): members with addr removed, and whether
    the shown pointer should be cleared (it pointed at addr). addr not present
    -> members unchanged, clear_shown False. Shared by `pull` and `evict`.
    """
    return ([a for a in members if a != addr], shown == addr)


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


def log(msg):
    """Append a timestamped debug line. No-op if SCRATCHPAD_DEBUG=0 or on error."""
    if not LOG_ENABLED:
        return
    try:
        ts = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
        with open(LOG_FILE, "a", encoding="utf-8") as fh:
            fh.write(f"{ts} {msg}\n")
    except OSError:
        pass


def _desc(by_addr, addr):
    """Short human description of a window address for the debug log:
    '0xdeadbeef [firefox] ws=4', or '<none>' / '<closed>' for missing ones."""
    if not addr:
        return "<none>"
    win = by_addr.get(addr)
    if win is None:
        return f"{addr[:10]} <closed>"
    cls = win.get("class") or win.get("initialClass") or "?"
    ws = (win.get("workspace") or {}).get("name") or "?"
    return f"{addr[:10]} [{cls}] ws={ws}"


def read_state():
    """Return (addr, show_ws): the pulled-out member and the workspace id it was
    shown on. show_ws lets cycle() tell a still-shown window from one the user
    moved off (extracted). Old single-field state files read as (addr, None)."""
    try:
        with open(STATE_FILE, encoding="utf-8") as fh:
            raw = fh.read().strip()
    except OSError:
        return (None, None)
    if not raw:
        return (None, None)
    parts = raw.split("\t")
    addr = parts[0] or None
    ws = parts[1] if len(parts) > 1 and parts[1] not in ("", "None") else None
    return (addr, ws)


def write_state(addr, ws=None):
    line = "" if not addr else (addr if ws is None else f"{addr}\t{ws}")
    with open(STATE_FILE, "w", encoding="utf-8") as fh:
        fh.write(line)


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


def workspace_id(win):
    return (win.get("workspace") or {}).get("id")


def released_by_move(cur_ws_name, cur_ws_id, show_ws):
    """True if a shown window was moved off its show-workspace by the user -- it
    has been extracted from the pad and must be forgotten (not re-hidden).

    cur_ws_name / cur_ws_id : the window's CURRENT workspace (name + id).
    show_ws                 : the workspace id (as str) the cycler showed it on.

    Returns False when we can't tell (no recorded show_ws / no current ws) or the
    stale check already covers it (window is back in the special ws). Pure;
    unit-tested in scratchpad_cycle_test.py."""
    if show_ws is None or cur_ws_name is None:
        return False
    if cur_ws_name == SPECIAL_WS:
        return False
    return str(cur_ws_id) != str(show_ws)


def cycle():
    clients = hyprctl_json("clients") or []
    by_addr = {c["address"]: c for c in clients}

    hidden = [c["address"] for c in clients if workspace_name(c) == SPECIAL_WS]

    shown, shown_ws = read_state()
    prior_members = read_members()
    log("=== cycle ===")
    log(f"  read  shown={_desc(by_addr, shown)} show_ws={shown_ws}")
    log(f"  file  members={[_desc(by_addr, a) for a in prior_members]}")
    log(f"  live  hidden(in {SPECIAL_WS})={[_desc(by_addr, a) for a in hidden]}")
    released = None
    # Drop a stale pointer: window closed, or already back in the special ws.
    if shown and (shown not in by_addr or workspace_name(by_addr[shown]) == SPECIAL_WS):
        log(f"  drop stale shown={_desc(by_addr, shown)} (closed or already in pad)")
        shown = None
    # Release: the user moved the shown window off its show-workspace -> it has
    # been extracted; forget it so plan() won't re-hide it and reset won't grab
    # it. This is the fix for "moved to ws N but it won't stick".
    elif shown and released_by_move(workspace_name(by_addr[shown]),
                                    workspace_id(by_addr[shown]), shown_ws):
        log(f"  release shown={_desc(by_addr, shown)} (moved off show-ws {shown_ws}; extracted)")
        released = shown
        shown = None

    # A released window must also leave the membership set, else update_members
    # re-adds it (it's live) and reset would recapture it.
    if released:
        prior_members = [a for a in prior_members if a != released]

    # Keep the membership set fresh so `reset` can find every out member.
    fresh = update_members(prior_members, hidden, shown, by_addr)
    write_members(fresh)
    log(f"  keep  members={[_desc(by_addr, a) for a in fresh]}")

    to_hide, to_show, new_state = plan(hidden, shown)
    log(f"  plan  to_hide={_desc(by_addr, to_hide)}  to_show={_desc(by_addr, to_show)}"
        f"  new_state={_desc(by_addr, new_state)}")

    if to_hide is None and to_show is None and new_state is None and not hidden and not shown:
        notify("empty")
        write_state(None)
        log("  act   empty; nothing to do")
        return

    if to_hide:
        # follow = false -> silent move (movetoworkspacesilent). Without it the
        # move FOLLOWS the window and surfaces the special pane on the monitor,
        # leaving the "hidden" window on screen.
        log(f"  act   HIDE {_desc(by_addr, to_hide)} -> {SPECIAL_WS}")
        dispatch(f'hl.dsp.window.move({{ workspace = "{SPECIAL_WS}", '
                 f'follow = false, window = "address:{to_hide}" }})')
    show_ws = None
    if to_show:
        show_ws = str((hyprctl_json("activeworkspace") or {}).get("id"))
        log(f"  act   SHOW {_desc(by_addr, to_show)} -> ws {show_ws}")
        dispatch(f'hl.dsp.window.move({{ workspace = "{show_ws}", window = "address:{to_show}" }})')
        dispatch(f'hl.dsp.focus({{ window = "address:{to_show}" }})')

    write_state(new_state, show_ws)
    log(f"  wrote shown={new_state[:10] if new_state else '<none>'} show_ws={show_ws}")


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

    shown, _ = read_state()
    candidates = set(read_members())
    if shown:
        candidates.add(shown)

    log("=== reset ===")
    log(f"  candidates={[_desc(by_addr, a) for a in sorted(candidates)]}")

    out = [a for a in candidates
           if a in by_addr and workspace_name(by_addr[a]) != SPECIAL_WS]
    log(f"  out(stash back)={[_desc(by_addr, a) for a in sorted(out)]}")
    for addr in sorted(out):
        # follow = false -> silent move; otherwise the special pane surfaces and
        # the window stays visible instead of being stashed out of sight.
        dispatch(f'hl.dsp.window.move({{ workspace = "{SPECIAL_WS}", '
                 f'follow = false, window = "address:{addr}" }})')

    # Prune closed windows from the tracked set; nothing is pulled out now.
    write_members(a for a in candidates if a in by_addr)
    write_state(None)
    notify(f"stashed {len(out)}" if out else "nothing out")
    log(f"  stashed {len(out)}; wrote shown=<none>")


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "cycle"
    if cmd == "reset":
        reset()
    else:
        cycle()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
