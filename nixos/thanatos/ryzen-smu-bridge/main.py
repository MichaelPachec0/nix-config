"""Thin I/O driver for the Ryzen SMU fan bridge. Spawns ryzen_monitor, republishes
the influx frame for Quickshell, and writes /run/thinkfan/temp from decide()."""
from __future__ import annotations

import glob
import os
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time

import fanbridge as fb


def resolve_tctl_path(hwmon_root: str = "/sys/class/hwmon") -> str | None:
    """Return the zenpower Tctl tempN_input path, or None if zenpower is absent."""
    for hw in sorted(glob.glob(os.path.join(hwmon_root, "hwmon*"))):
        try:
            with open(os.path.join(hw, "name")) as f:
                if f.read().strip() != "zenpower":
                    continue
        except OSError:
            continue
        for label in sorted(glob.glob(os.path.join(hw, "temp*_label"))):
            try:
                with open(label) as f:
                    if f.read().strip() != "Tctl":
                        continue
            except OSError:
                continue
            return label.replace("_label", "_input")
    return None


def read_millideg(path: str | None) -> float | None:
    """Read an integer-millidegree sysfs file and return whole C, or None."""
    if path is None:
        return None
    try:
        with open(path) as f:
            return int(f.read().strip()) / 1000.0
    except (OSError, ValueError):
        return None


def read_ac_online(path: str = "/sys/class/power_supply/AC/online") -> bool:
    try:
        with open(path) as f:
            return f.read().strip() == "1"
    except OSError:
        return False


def read_override(path: str = "/run/thinkfan/mode") -> str | None:
    try:
        with open(path) as f:
            val = f.read().strip()
    except OSError:
        return None
    return val if val in fb.VALID_MODES else None


def atomic_write(path: str, text: str, mode: int = 0o644) -> None:
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


RUN_RYZEN = "/run/ryzen-monitor"
FIFO = os.path.join(RUN_RYZEN, "pm.fifo")
INFLUX_OUT = os.path.join(RUN_RYZEN, "latest.influx")
THINKFAN_TEMP = "/run/thinkfan/temp"
MODE_PATH = "/run/thinkfan/mode"
FRAME_TERMINATOR = "package_totalcorepower"


class Shared:
    """Latest SMU frame values, updated by the reader thread, read by the loop."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.cpu_thm: float | None = None
        self.peak: float | None = None
        self.frame_ts: float | None = None  # monotonic time of last full frame
        self.alive = True


def sd_notify(msg: str) -> None:
    """Minimal sd_notify; no-op when not run under systemd Type=notify."""
    addr = os.environ.get("NOTIFY_SOCKET")
    if not addr:
        return
    if addr[0] == "@":
        addr = "\0" + addr[1:]
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as s:
            s.connect(addr)
            s.sendall(msg.encode())
    except OSError:
        pass


def reader_thread(shared: Shared) -> None:
    """Read the ryzen_monitor fifo, republish whole frames, update shared state."""
    buf: list[str] = []
    try:
        with open(FIFO) as fifo:
            for line in fifo:
                buf.append(line)
                if FRAME_TERMINATOR in line:
                    text = "".join(buf)
                    buf = []
                    atomic_write(INFLUX_OUT, text, 0o644)  # Quickshell contract
                    frame = fb.parse_frame(text)
                    with shared.lock:
                        shared.cpu_thm = frame.get("cpu_thm")
                        shared.peak = frame.get("package_peaktemperature")
                        shared.frame_ts = time.monotonic()
    except OSError:
        pass
    finally:
        with shared.lock:
            shared.alive = False  # EOF: ryzen_monitor gone -> let systemd restart us


def main() -> int:
    os.makedirs(RUN_RYZEN, exist_ok=True)
    os.makedirs(os.path.dirname(THINKFAN_TEMP), exist_ok=True)
    # seed a safe default so thinkfan has a value immediately
    atomic_write(THINKFAN_TEMP, "60000\n", 0o644)

    for stale in (FIFO, INFLUX_OUT):
        try:
            os.unlink(stale)
        except OSError:
            pass

    proc = subprocess.Popen(["ryzen_monitor", "-u", "2", "-e", FIFO])

    def _term(*_: object) -> None:
        proc.terminate()
    signal.signal(signal.SIGTERM, _term)
    signal.signal(signal.SIGINT, _term)

    # wait for ryzen_monitor to create the fifo
    for _ in range(100):
        if os.path.exists(FIFO):
            break
        time.sleep(0.1)
    if not os.path.exists(FIFO):
        proc.terminate()
        return 1

    shared = Shared()
    threading.Thread(target=reader_thread, args=(shared,), daemon=True).start()

    tctl_path = resolve_tctl_path()
    state = fb.State(ema=None, hot_since=None)
    last_ac: bool | None = None

    sd_notify("READY=1")
    try:
        while True:
            if proc.poll() is not None:
                return 1  # ryzen_monitor died -> restart whole unit
            with shared.lock:
                if not shared.alive:
                    return 1
                cpu_thm, peak, frame_ts = shared.cpu_thm, shared.peak, shared.frame_ts
            now = time.monotonic()
            frame_age = float("inf") if frame_ts is None else now - frame_ts
            ac = read_ac_online()
            # AC edge clears a per-power-session override
            if last_ac is not None and ac != last_ac:
                try:
                    os.unlink(MODE_PATH)
                except OSError:
                    pass
            last_ac = ac
            try:
                inp = fb.Inputs(
                    cpu_thm=cpu_thm, peak=peak, tctl=read_millideg(tctl_path),
                    frame_age=frame_age, ac_online=ac,
                    override=read_override(MODE_PATH), now=now)
                dec = fb.decide(inp, state)
                state = dec.state
                atomic_write(THINKFAN_TEMP, f"{dec.published_mc}\n", 0o644)
            except Exception:  # fail toward cold; never die on one bad tick
                atomic_write(THINKFAN_TEMP, f"{fb.FAIL_SAFE_MC}\n", 0o644)
            sd_notify("WATCHDOG=1")
            time.sleep(1.0)
    finally:
        proc.terminate()


if __name__ == "__main__":
    sys.exit(main())
