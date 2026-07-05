"""Thin I/O driver for the Ryzen SMU fan bridge. Spawns ryzen_monitor, republishes
the influx frame for Quickshell, and writes /run/thinkfan/temp from decide()."""
from __future__ import annotations

import glob
import os
import tempfile

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
