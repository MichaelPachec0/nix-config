"""Manifest of store files each app maps. One JSON file, atomic writes."""

from __future__ import annotations

import json
import os
from typing import Callable, Iterable

# Any other version is discarded, not migrated. It is a cache.
MANIFEST_VERSION = 1

Manifest = dict[str, list[str]]


def load(path: str) -> Manifest:
    """Read manifest. Missing/corrupt/stale-version yields {}."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(data, dict) or data.get("version") != MANIFEST_VERSION:
        return {}
    apps = data.get("apps")
    if not isinstance(apps, dict):
        return {}
    out: Manifest = {}
    for app, files in apps.items():
        if isinstance(app, str) and isinstance(files, list):
            out[app] = sorted({f for f in files if isinstance(f, str)})
    return out


def merge(base: Manifest, app: str, files: Iterable[str]) -> Manifest:
    """Union files into app's entry. Returns a new Manifest."""
    out: Manifest = {k: list(v) for k, v in base.items()}
    out[app] = sorted(set(out.get(app, [])) | set(files))
    return out


def prune(
    m: Manifest, exists: Callable[[str], bool] = os.path.exists
) -> Manifest:
    """Drop paths that no longer exist.

    Rebuild or GC invalidates recorded paths. Keeps the manifest bounded.
    """
    return {app: [f for f in files if exists(f)] for app, files in m.items()}


def save(path: str, m: Manifest) -> None:
    """Atomically write the manifest. Creates parent dirs."""
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(
            {"version": MANIFEST_VERSION, "apps": m}, f, indent=1, sort_keys=True
        )
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
