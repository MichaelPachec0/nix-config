"""Seed: derive an app's store files without running it.

Wrapper resolution is load-bearing. nixpkgs hides the real binary:

    ldd on PATH rofi (makeBinaryWrapper ELF)  ->  3 files,  2.6 MB
    ldd on rofi-unwrapped/bin/rofi            -> 60 files, 23.1 MB

Getting it wrong does not error, it silently seeds nothing. Both wrapper
kinds are tested.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from typing import Callable

Runner = Callable[..., "subprocess.CompletedProcess[str]"]

STORE_PREFIX = "/nix/store/"

# Nix store hash: 32 chars base32, no e/o/u/t.
STORE_RE = re.compile(
    STORE_PREFIX.encode() + rb"[0-9a-df-np-sv-z]{32}-[^\x00'\"\s]+"
)


def store_strings(path: str) -> list[str]:
    """Every /nix/store path embedded in a file, in order, deduped.

    Raw bytes covers both wrapper kinds: shell wrappers hold paths as text,
    makeBinaryWrapper holds them in .rodata.
    """
    try:
        with open(path, "rb") as f:
            blob = f.read()
    except OSError:
        return []
    seen: list[str] = []
    for match in STORE_RE.findall(blob):
        s = match.decode("utf-8", "replace").rstrip("'\"")
        if s not in seen:
            seen.append(s)
    return seen


def real_binary(
    app: str,
    which: Callable[[str], str | None] = shutil.which,
    strings: Callable[[str], list[str]] = store_strings,
) -> str | None:
    """Resolve app on PATH through any nixpkgs wrapper to the real ELF.

    Picks the embedded store path that is an executable with the same
    basename. Falls back to the PATH entry, correct for unwrapped binaries.
    """
    found = which(app)
    if found is None:
        return None
    entry = os.path.realpath(found)
    base = os.path.basename(entry)
    for cand in strings(entry):
        if cand == entry or os.path.basename(cand) != base:
            continue
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return os.path.realpath(cand)
    return entry


def ldd_closure(elf: str, run: Runner = subprocess.run) -> list[str]:
    """Store paths of the shared libs elf links against."""
    try:
        proc = run(
            ["ldd", elf], capture_output=True, text=True, timeout=30, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return []
    out: set[str] = set()
    for line in proc.stdout.splitlines():
        for tok in line.split():
            if tok.startswith(STORE_PREFIX) and os.path.isfile(tok):
                out.add(os.path.realpath(tok))
    return sorted(out)


def seed(app: str) -> list[str]:
    """Store files derivable for app without running it."""
    elf = real_binary(app)
    if elf is None:
        return []
    files: set[str] = {elf}
    files.update(ldd_closure(elf))
    return sorted(files)
