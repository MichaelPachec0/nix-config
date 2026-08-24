"""Learn which store files the apps actually map, from /proc.

ldd cannot see dlopen'd plugins or data files, and those are most of the
working set here: omni.ja 53 MB, locale-archive 222 MB, one CJK font 55 MB.

Scan costs under 10 ms, so the timer can be frequent. rofi only lives for
about two seconds at a time.
"""

from __future__ import annotations

import os
from typing import Sequence

DELETED = " (deleted)"


def norm_basename(name: str) -> str:
    """Strip the nixpkgs wrapper decoration: .<app>-wrapped -> <app>."""
    return name.lstrip(".").removesuffix("-wrapped")


def app_for(base: str, apps: Sequence[str]) -> str | None:
    """Match a process to an app by exe basename.

    Basename only, never a cmdline substring: "profile" contains "rofi", and
    that once attributed 475 MB to rofi while rofi was not running.

    Accepts firefox-bin for firefox. Rejects rofimoji for rofi.
    """
    for app in apps:
        if base == app or base.startswith(app + "-"):
            return app
    return None


def exe_basename(procfs: str, pid: str) -> str | None:
    """Normalised exe basename for a pid, or None."""
    try:
        exe = os.readlink(os.path.join(procfs, pid, "exe"))
    except OSError:
        return None
    base = os.path.basename(exe)
    if base.endswith(DELETED):
        base = base[: -len(DELETED)]
    return norm_basename(base)


def mapped_store_files(maps_path: str) -> set[str]:
    """Store files backing the mappings in one /proc/<pid>/maps."""
    try:
        with open(maps_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return set()
    out: set[str] = set()
    for line in lines:
        idx = line.find("/nix/store/")
        if idx <= 0:
            continue
        path = line[idx:].rstrip("\n")
        # Deleted mapping: path is gone, would be pruned anyway.
        if path.endswith(DELETED):
            continue
        out.add(path)
    return out


def scan(apps: Sequence[str], procfs: str = "/proc") -> dict[str, list[str]]:
    """Map each app to the store files its processes currently map.

    Apps with no processes are omitted, not given empty lists, so a merge
    never overwrites a good record with nothing.
    """
    found: dict[str, set[str]] = {}
    try:
        pids = os.listdir(procfs)
    except OSError:
        return {}
    for pid in pids:
        if not pid.isdigit():
            continue
        base = exe_basename(procfs, pid)
        if base is None:
            continue
        app = app_for(base, apps)
        if app is None:
            continue
        files = mapped_store_files(os.path.join(procfs, pid, "maps"))
        if files:
            found.setdefault(app, set()).update(files)
    return {app: sorted(files) for app, files in found.items()}
