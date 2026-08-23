"""Resolve a nixpkgs wrapper to the real ELF. Build time only.

Every tracked package ships a makeBinaryWrapper ELF at bin/<name>; ldd on it
returns 2 libraries against 8, 60 and 99 for the real binaries. Packaging is
not uniform, so two mechanisms:

    kitty, quickshell   .<name>-wrapped sibling
    rofi                embedded store string (real binary is another drv)

Both are heuristics. The per-app floor in the seed derivation is what makes
this safe: a wrong pick collapses the file count and fails the build.
"""

from __future__ import annotations

import os
import re

STORE_PREFIX = "/nix/store"


def _store_re() -> re.Pattern[bytes]:
    return re.compile(
        re.escape(STORE_PREFIX.encode()) + rb"/[0-9a-df-np-sv-z]{32}-[^\x00'\"\s]+"
    )


def sibling(path: str) -> str | None:
    """The .<name>-wrapped sibling, if nixpkgs made one."""
    d, n = os.path.split(path)
    cand = os.path.join(d, f".{n}-wrapped")
    return cand if os.path.exists(cand) else None


def from_strings(path: str, name: str) -> str | None:
    """First embedded store path that is an executable file named `name`.

    share/ is skipped: rofi's wrapper embeds a merged XDG_DATA_DIRS containing
    a whole tor-browser, and walking it returned 338 MB of the wrong thing.
    """
    try:
        with open(path, "rb") as f:
            blob = f.read()
    except OSError:
        return None
    for m in _store_re().finditer(blob):
        cand = m.group(0).decode("utf-8", "replace")
        if "/share/" in cand or cand == path:
            continue
        if os.path.basename(cand) != name:
            continue
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


def resolve(path: str) -> str:
    """The real ELF behind `path`. Returns `path` unchanged if not a wrapper."""
    name = os.path.basename(path)
    return sibling(path) or from_strings(path, name) or path
