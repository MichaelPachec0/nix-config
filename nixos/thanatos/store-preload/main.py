"""store-preload: warm the store working set of a few apps at session start.

  seed    print what the resolver derives per app
  record  merge currently-mapped files into the manifest
  warm    read seed + manifest into page cache, report residency
  status  report residency without reading anything
"""

from __future__ import annotations

import argparse
import os
import sys
import time

import manifest
import record
import resolve
import warm as warmlib

DEFAULT_APPS = ["rofi", "kitty", "quickshell", "firefox-devedition"]
DEFAULT_WORKERS = 4
DEFAULT_MAX_BYTES = 2 << 30


def _state_path() -> str:
    """Manifest path under XDG_STATE_HOME.

    /home is a separate btrfs fs and survives the stage-1 root rollback, so
    no /persist entry is needed.
    """
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "store-preload", "manifest.json")


def _mb(n: int) -> str:
    return f"{n / 2**20:.1f} MB"


def _ordered_files(apps: list[str], man: manifest.Manifest) -> list[str]:
    """Union of seed and manifest, in app order, deduped.

    First app is warmed first. Put what you wait on at the top.
    """
    seen: set[str] = set()
    out: list[str] = []
    for app in apps:
        for path in list(resolve.seed(app)) + list(man.get(app, [])):
            if path not in seen:
                seen.add(path)
                out.append(path)
    return out


def _residency(files: list[str]) -> tuple[int, int]:
    """(resident bytes, total bytes) over files."""
    res = 0
    total = 0
    for path in files:
        r, s = warmlib.resident(path)
        res += r
        total += s
    return res, total


def cmd_seed(args: argparse.Namespace) -> int:
    for app in args.apps:
        files = resolve.seed(app)
        size = sum(os.path.getsize(f) for f in files if os.path.exists(f))
        print(f"{app:12} {len(files):5d} files  {_mb(size)}")
    return 0


def cmd_record(args: argparse.Namespace) -> int:
    path = args.state
    was_man = manifest.load(path)
    was_roots = manifest.load_roots(path)
    man = manifest.restrict(manifest.prune(was_man), args.apps)
    roots = {a: r for a, r in was_roots.items() if a in args.apps}

    found = record.scan(args.apps)
    reset: list[str] = []
    for app, files in sorted(found.items()):
        # An app's store root is its generation stamp. Retained generations
        # keep the old closure on disk, so prune cannot see a rebuild.
        stamp = resolve.store_root(resolve.real_binary(app))
        if stamp is not None and roots.get(app) != stamp:
            man = manifest.replace(man, app, files)
            roots[app] = stamp
            reset.append(app)
        else:
            man = manifest.merge(man, app, files)

    total = sum(len(v) for v in man.values())
    seen = ", ".join(f"{a}:{len(f)}" for a, f in sorted(found.items())) or "none running"
    if man == was_man and roots == was_roots:
        # No write, no fsync. This runs every 30s on a laptop.
        print(f"store-preload: {seen}; unchanged, manifest {total} files")
        return 0
    manifest.save(path, man, roots)
    note = f"; reset {', '.join(reset)} (new generation)" if reset else ""
    print(f"store-preload: recorded {seen}; manifest now {total} files{note}")
    return 0


def cmd_warm(args: argparse.Namespace) -> int:
    man = manifest.prune(manifest.load(args.state))
    files = _ordered_files(args.apps, man)
    todo, planned, skipped = warmlib.plan_reads(files, args.max_bytes)

    # Measured over the whole union, not the planned subset: quickshell is
    # already running and is most of the bytes, so the subset reads ~100%
    # even when every reader died. The delta is the number that can fail.
    before, union = _residency(files)
    start = time.monotonic()
    read = warmlib.warm(todo, args.workers)
    elapsed = time.monotonic() - start
    after, _ = _residency(files)

    pct = (100.0 * after / union) if union else 0.0
    rate = (read / 2**20 / elapsed) if elapsed > 0 else 0.0
    print(
        f"store-preload: {len(todo)} files, {_mb(planned)} in {elapsed:.2f}s "
        f"({rate:.0f} MB/s); resident {_mb(before)} -> {_mb(after)} "
        f"(+{_mb(after - before)}, {pct:.1f}% of {_mb(union)})"
    )
    if skipped:
        print(f"store-preload: skipped {_mb(skipped)} to stay under the cap")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    man = manifest.prune(manifest.load(args.state))
    files = _ordered_files(args.apps, man)
    # Same union denominator as warm, so the two percentages compare.
    res, total = _residency(files)
    pct = (100.0 * res / total) if total else 0.0
    print(
        f"store-preload: {len(files)} files, {_mb(total)}; "
        f"resident {_mb(res)} ({pct:.1f}%)"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="store-preload")
    # Comma-separated, not nargs="+": a greedy list swallows the subcommand.
    parser.add_argument(
        "--apps", type=lambda v: [a for a in v.split(",") if a],
        default=DEFAULT_APPS,
    )
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    parser.add_argument("--state", default=_state_path())
    sub = parser.add_subparsers(dest="cmd", required=True)
    for name, fn in (
        ("seed", cmd_seed),
        ("record", cmd_record),
        ("warm", cmd_warm),
        ("status", cmd_status),
    ):
        sub.add_parser(name).set_defaults(func=fn)
    args = parser.parse_args(argv)
    result: int = args.func(args)
    return result


if __name__ == "__main__":
    sys.exit(main())
