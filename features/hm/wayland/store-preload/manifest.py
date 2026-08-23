"""Manifest of store files each app maps. One JSON file, atomic writes."""

from __future__ import annotations

import json
import os
from typing import Any, Callable, Iterable

# Any other version is discarded, not migrated. It is a cache.
# v2 added the per-app generation stamp (root).
MANIFEST_VERSION = 2

Manifest = dict[str, list[str]]
Roots = dict[str, str]


def _read(path: str) -> tuple[Manifest, Roots]:
    """Parse the file into (files per app, store root per app)."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            data: Any = json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}, {}
    if not isinstance(data, dict) or data.get("version") != MANIFEST_VERSION:
        return {}, {}
    apps = data.get("apps")
    if not isinstance(apps, dict):
        return {}, {}
    files_out: Manifest = {}
    roots_out: Roots = {}
    for app, entry in apps.items():
        if not isinstance(app, str) or not isinstance(entry, dict):
            continue
        files = entry.get("files")
        if not isinstance(files, list):
            continue
        files_out[app] = sorted({f for f in files if isinstance(f, str)})
        root = entry.get("root")
        if isinstance(root, str) and root:
            roots_out[app] = root
    return files_out, roots_out


def load(path: str) -> Manifest:
    """Read manifest. Missing/corrupt/stale-version yields {}."""
    return _read(path)[0]


def load_roots(path: str) -> Roots:
    """Read the per-app generation stamps. Same failure modes as load."""
    return _read(path)[1]


def merge(base: Manifest, app: str, files: Iterable[str]) -> Manifest:
    """Union files into app's entry. Returns a new Manifest."""
    out: Manifest = {k: list(v) for k, v in base.items()}
    out[app] = sorted(set(out.get(app, [])) | set(files))
    return out


def replace(base: Manifest, app: str, files: Iterable[str]) -> Manifest:
    """Drop app's entry and set it to files. Returns a new Manifest.

    Used when the app's store root changed: the old closure still exists
    (old generations are retained) so prune would never drop it.
    """
    out: Manifest = {k: list(v) for k, v in base.items()}
    out[app] = sorted(set(files))
    return out


def restrict(m: Manifest, apps: Iterable[str]) -> Manifest:
    """Keep only the listed apps. Renaming an app must not orphan its key."""
    keep = set(apps)
    return {app: list(files) for app, files in m.items() if app in keep}


def prune(
    m: Manifest, exists: Callable[[str], bool] = os.path.exists
) -> Manifest:
    """Drop paths that no longer exist.

    Only catches GC, not rebuilds: retained generations keep old paths alive.
    The per-app root stamp handles rebuilds.
    """
    return {app: [f for f in files if exists(f)] for app, files in m.items()}


def save(path: str, m: Manifest, roots: Roots) -> None:
    """Atomically write the manifest. Creates parent dirs."""
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    apps = {
        app: {"root": roots.get(app, ""), "files": files}
        for app, files in m.items()
    }
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(
            {"version": MANIFEST_VERSION, "apps": apps},
            f,
            indent=1,
            sort_keys=True,
        )
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
