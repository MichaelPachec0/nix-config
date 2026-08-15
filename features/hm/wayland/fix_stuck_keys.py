#!/usr/bin/env python3
"""fix-stuck-keys: clear keyboard keys the kernel wrongly believes are held.

PS/2 keyboards have a limited n-key rollover. When many keys go down at once
(a cat sitting on the laptop, a palm on the deck) the i8042 matrix ghosts and
the controller drops RELEASE scancodes. The kernel never sees them, so its
per-device key bitmap keeps reporting those keys as down forever.

The loudest symptom is not the keyboard -- it is the *touchpad going dead*.
libinput's disable-while-typing gates touchpads only (pointing sticks are
excluded by design), so a permanently-"typing" keyboard mutes the touchpad
while the trackpoint keeps working. That asymmetry reads as a broken touchpad
and sends you looking in entirely the wrong place. A stuck *modifier* is worse
still: every keystroke becomes a chord and fires compositor binds.

The fix is to inject the missing release. Writing an input_event to
/dev/input/eventN reaches input_inject_event() in the kernel, which updates the
device's key bitmap and fans the release out to every handler, including
libinput. Releasing a key that is already up is silently dropped, so this is
idempotent and safe to run at any time. Nothing is restarted and no device is
re-initialised, unlike the `drvctl reconnect` / service-restart alternatives.

Injecting into the *physical* keyboard is usually enough even when a remapper
sits in front of it: kanata holds an EVIOCGRAB on the real device, sees the
injected release, and emits a matching release on its own virtual device. Each
device is still handled independently here, in case only the virtual one is
stuck.

Why not a keybind? A keybind cannot be relied on for this fault. If the bound
trigger key is itself stuck, libinput filters kernel autorepeat and never
delivers a fresh press, so the bind is dead. If a modifier is stuck, every bind
fires wrong. Hence: a watchdog (--daemon) plus a plain CLI, not a hotkey.

Daemon safety. A legitimately held key is indistinguishable from a stuck one by
bitmap alone, so releases are gated three ways:
  * the cat signature -- several non-modifier keys held continuously; ordinary
    typing does not park 3+ keys down for ten seconds,
  * a long-hold straggler rule for a lone survivor, on a much longer timer,
  * a GPU-busy gate -- while the GPU is genuinely working (a game, video), keys
    held down are presumed deliberate and nothing is touched.
The CLI path (no --daemon) applies none of these: an explicit run means the
user has already decided.

Pure decision logic (HeldTracker / decide_releases / is_keyboard_code) is
covered by fix_stuck_keys_test.py; the rest is ioctl and sysfs glue.
"""
from __future__ import annotations

import argparse
import fcntl
import glob
import os
import struct
import subprocess
import sys
import time

# struct input_event on 64-bit: struct timeval {long, long}, u16 type, u16 code,
# s32 value.
EVENT_FORMAT = "qqHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)

EV_SYN = 0x00
EV_KEY = 0x01
SYN_REPORT = 0x00
KEY_RELEASE = 0

# KEY_MAX is 0x2ff, so the kernel's key bitmap is 768 bits = 96 bytes.
KEY_BITMAP_BYTES = 96
# Codes at/above BTN_MISC are buttons (mouse, tablet, gamepad), not keyboard
# keys. Never inject there: a held BTN_LEFT is a drag in progress, and force-
# releasing it mid-gesture would corrupt real user input.
BTN_MISC = 0x100

_IOC_READ = 2


def _ioc_read(nr, size):
    """Encode a _IOR('E', nr, size) ioctl request number."""
    return (_IOC_READ << 30) | (size << 16) | (ord("E") << 8) | nr


EVIOCGNAME = lambda size: _ioc_read(0x06, size)  # noqa: E731
EVIOCGKEY = lambda size: _ioc_read(0x18, size)  # noqa: E731

# Modifiers are excluded from the "several keys are down" count -- holding
# Ctrl+Shift while typing is completely normal -- but they ARE released once a
# rule fires, since a stuck modifier is the most disruptive case of all.
MODIFIER_CODES = frozenset(
    {
        29,  # KEY_LEFTCTRL
        42,  # KEY_LEFTSHIFT
        54,  # KEY_RIGHTSHIFT
        56,  # KEY_LEFTALT
        97,  # KEY_RIGHTCTRL
        100,  # KEY_RIGHTALT
        125,  # KEY_LEFTMETA
        126,  # KEY_RIGHTMETA
    }
)

# Defaults; every one is overridable from the CLI (and from the Nix module).
DEFAULT_POLL_S = 2.0
# Cat signature: this many non-modifier keys, all continuously down for this
# long. Ten seconds is far past any real chord but well under the window in
# which a muted touchpad becomes annoying.
DEFAULT_CAT_KEYS = 3
DEFAULT_CAT_HOLD_S = 10.0
# Lone straggler: a single key still down after this long. Deliberately much
# longer, because one held key is the shape of a legitimate long press.
DEFAULT_LONE_HOLD_S = 120.0
# Above this GPU utilisation, assume the machine is being actively driven
# (game, video) and leave held keys alone. Renoir idles around 0-5%.
DEFAULT_GPU_BUSY_PCT = 45

GPU_BUSY_GLOB = "/sys/class/drm/card*/device/gpu_busy_percent"


# ---------------------------------------------------------------------------
# Pure helpers (unit-tested)
# ---------------------------------------------------------------------------
def is_keyboard_code(code):
    """True for real keyboard keys, i.e. everything below BTN_MISC."""
    return 0 < code < BTN_MISC


class HeldTracker:
    """Track, per key code, the moment it was first seen continuously down.

    Clock is injected (a zero-arg callable returning a monotonic float) so the
    timing is deterministic under test -- no sleeps.

    A key that disappears from the bitmap and comes back is a genuine release
    plus a genuine press, so its timer restarts from zero. That is what makes
    ordinary typing invisible to the rules: no key survives long enough.
    """

    def __init__(self, now_fn):
        self._now = now_fn
        self._since = {}

    def update(self, codes):
        """Fold a fresh bitmap reading in; returns {code: held-since stamp}."""
        now = self._now()
        codes = {c for c in codes if is_keyboard_code(c)}
        for code in codes:
            self._since.setdefault(code, now)
        for code in list(self._since):
            if code not in codes:
                del self._since[code]
        return dict(self._since)

    def forget(self, codes):
        """Drop tracking for codes we just released, so timers restart clean."""
        for code in codes:
            self._since.pop(code, None)


def decide_releases(held_since, now, gpu_busy_pct, cfg):
    """Pick the key codes to force-release. Pure; returns a sorted list.

    `held_since` maps code -> the timestamp it was first seen down.
    `gpu_busy_pct` is the current GPU utilisation, or None when unknown (an
    unreadable sysfs node must not silently disable the whole watchdog, so
    None is treated as idle).
    """
    if not held_since:
        return []

    # GPU gate first: while something is really using the GPU, held keys are
    # presumed deliberate. Cheapest possible answer, and it short-circuits the
    # riskiest case (a game holding movement keys).
    if gpu_busy_pct is not None and gpu_busy_pct >= cfg.gpu_busy_pct:
        return []

    ages = {code: now - stamp for code, stamp in held_since.items()}

    # Cat signature: enough non-modifier keys, all aged past the threshold.
    aged_nonmod = [
        code
        for code, age in ages.items()
        if code not in MODIFIER_CODES and age >= cfg.cat_hold_s
    ]
    if len(aged_nonmod) >= cfg.cat_keys:
        # Release everything held, modifiers included -- the whole bitmap is
        # untrustworthy once the matrix has ghosted.
        return sorted(ages)

    # Lone straggler: anything still down after the long timer.
    return sorted(code for code, age in ages.items() if age >= cfg.lone_hold_s)


class Config:
    """Thresholds for decide_releases; plain value object."""

    def __init__(
        self,
        cat_keys=DEFAULT_CAT_KEYS,
        cat_hold_s=DEFAULT_CAT_HOLD_S,
        lone_hold_s=DEFAULT_LONE_HOLD_S,
        gpu_busy_pct=DEFAULT_GPU_BUSY_PCT,
    ):
        self.cat_keys = cat_keys
        self.cat_hold_s = cat_hold_s
        self.lone_hold_s = lone_hold_s
        self.gpu_busy_pct = gpu_busy_pct


# ---------------------------------------------------------------------------
# evdev / sysfs glue
# ---------------------------------------------------------------------------
def event_devices():
    """Every /dev/input/eventN path, in numeric order."""

    def index(path):
        tail = os.path.basename(path)[len("event") :]
        return int(tail) if tail.isdigit() else -1

    return sorted(glob.glob("/dev/input/event*"), key=index)


def device_name(fd):
    buf = bytearray(256)
    try:
        fcntl.ioctl(fd, EVIOCGNAME(len(buf)), buf, True)
    except OSError:
        return "?"
    return buf.split(b"\x00")[0].decode("utf-8", "replace")


def keys_down(fd):
    """Key codes the kernel currently believes are held on this device."""
    buf = bytearray(KEY_BITMAP_BYTES)
    fcntl.ioctl(fd, EVIOCGKEY(len(buf)), buf, True)
    return [
        byte * 8 + bit
        for byte in range(KEY_BITMAP_BYTES)
        for bit in range(8)
        if buf[byte] >> bit & 1
    ]


def scan():
    """[(path, name, [held keyboard codes])] for devices reporting keys down."""
    found = []
    for path in event_devices():
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue  # not ours to read; nothing to do about it
        try:
            codes = [c for c in keys_down(fd) if is_keyboard_code(c)]
            if codes:
                found.append((path, device_name(fd), codes))
        except OSError:
            continue  # device vanished or refuses EVIOCGKEY
        finally:
            os.close(fd)
    return found


def inject_releases(path, codes):
    """Write release events for `codes` into `path`. True when accepted.

    One SYN_REPORT terminates the batch so downstream consumers see a single
    coherent frame rather than one per key.
    """
    if not codes:
        return True
    payload = b"".join(
        struct.pack(EVENT_FORMAT, 0, 0, EV_KEY, code, KEY_RELEASE) for code in codes
    )
    payload += struct.pack(EVENT_FORMAT, 0, 0, EV_SYN, SYN_REPORT, 0)
    try:
        fd = os.open(path, os.O_RDWR)
    except OSError as exc:
        print(f"fix-stuck-keys: cannot open {path} for writing: {exc}", file=sys.stderr)
        return False
    try:
        os.write(fd, payload)
        return True
    except OSError as exc:
        print(f"fix-stuck-keys: inject failed on {path}: {exc}", file=sys.stderr)
        return False
    finally:
        os.close(fd)


def gpu_busy_percent():
    """Current GPU utilisation, or None when no amdgpu/radeon node is readable.

    Same sysfs node the task-bar's gpu-stats.sh reads.
    """
    for node in sorted(glob.glob(GPU_BUSY_GLOB)):
        try:
            with open(node) as handle:
                return int(handle.read().strip())
        except (OSError, ValueError):
            continue
    return None


def notify(codes, names):
    """Best-effort desktop notification. Never fatal -- this is a courtesy."""
    keys = ", ".join(str(c) for c in codes)
    where = ", ".join(sorted(set(names)))
    try:
        subprocess.run(
            [
                "notify-send",
                "--app-name=fix-stuck-keys",
                "--icon=input-keyboard",
                "Released stuck keys",
                f"codes {keys} on {where}",
            ],
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        pass


# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
def run_check():
    """Report held keys. Exit 1 when anything is down, 0 when clean."""
    found = scan()
    if not found:
        print("no stuck keys")
        return 0
    for path, name, codes in found:
        print(f"{path}\t{name}\tdown: {codes}")
    return 1


def run_once(quiet=False):
    """Unconditionally release every held keyboard key. Exit 0 when clean."""
    found = scan()
    if not found:
        if not quiet:
            print("no stuck keys")
        return 0
    ok = True
    for path, name, codes in found:
        if inject_releases(path, codes):
            if not quiet:
                print(f"released {codes} on {path} ({name})")
        else:
            ok = False
    # Injection is asynchronous through the input core; give it a moment before
    # reporting, so the verification below reflects the post-release state.
    time.sleep(0.2)
    remaining = scan()
    if remaining:
        for path, name, codes in remaining:
            print(f"fix-stuck-keys: still held on {path} ({name}): {codes}",
                  file=sys.stderr)
        return 1
    return 0 if ok else 1


def run_daemon(cfg, poll_s):
    """Poll the key bitmaps and release only what the heuristics condemn."""
    trackers = {}
    gated = False  # log the GPU gate on transition only, never every poll
    while True:
        found = scan()
        live = {path for path, _, _ in found}
        for path in list(trackers):
            if path not in live:
                del trackers[path]

        busy = gpu_busy_percent()
        blocking = (
            found and busy is not None and busy >= cfg.gpu_busy_pct
        )
        if blocking and not gated:
            print(f"fix-stuck-keys: gpu busy ({busy}%), leaving held keys alone",
                  flush=True)
        gated = bool(blocking)

        for path, name, codes in found:
            tracker = trackers.setdefault(path, HeldTracker(time.monotonic))
            held_since = tracker.update(codes)
            doomed = decide_releases(held_since, time.monotonic(), busy, cfg)
            if not doomed:
                continue
            print(f"fix-stuck-keys: releasing {doomed} on {path} ({name})", flush=True)
            if inject_releases(path, doomed):
                tracker.forget(doomed)
                notify(doomed, [name])
        time.sleep(poll_s)


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="fix-stuck-keys",
        description="Clear keyboard keys the kernel wrongly believes are held.",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--daemon",
        action="store_true",
        help="watch continuously and release only what the heuristics condemn",
    )
    mode.add_argument(
        "--check",
        action="store_true",
        help="report held keys without changing anything; exit 1 if any are held",
    )
    parser.add_argument("--quiet", action="store_true", help="suppress normal output")
    parser.add_argument("--poll-seconds", type=float, default=DEFAULT_POLL_S)
    parser.add_argument("--cat-keys", type=int, default=DEFAULT_CAT_KEYS)
    parser.add_argument("--cat-hold-seconds", type=float, default=DEFAULT_CAT_HOLD_S)
    parser.add_argument("--lone-hold-seconds", type=float, default=DEFAULT_LONE_HOLD_S)
    parser.add_argument("--gpu-busy-percent", type=int, default=DEFAULT_GPU_BUSY_PCT)
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.check:
        return run_check()
    if not args.daemon:
        return run_once(quiet=args.quiet)
    cfg = Config(
        cat_keys=args.cat_keys,
        cat_hold_s=args.cat_hold_seconds,
        lone_hold_s=args.lone_hold_seconds,
        gpu_busy_pct=args.gpu_busy_percent,
    )
    try:
        run_daemon(cfg, args.poll_seconds)
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
