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


def cmd_seed(args: argparse.Namespace) -> int:
    for app in args.apps:
        files = resolve.seed(app)
        size = sum(os.path.getsize(f) for f in files if os.path.exists(f))
        print(f"{app:12} {len(files):5d} files  {_mb(size)}")
    return 0


def cmd_record(args: argparse.Namespace) -> int:
    path = args.state
    man = manifest.prune(manifest.load(path))
    found = record.scan(args.apps)
    for app, files in found.items():
        man = manifest.merge(man, app, files)
    manifest.save(path, man)
    total = sum(len(v) for v in man.values())
    seen = ", ".join(f"{a}:{len(f)}" for a, f in sorted(found.items())) or "none running"
    print(f"store-preload: recorded {seen}; manifest now {total} files")
    return 0


def cmd_warm(args: argparse.Namespace) -> int:
    man = manifest.prune(manifest.load(args.state))
    files = _ordered_files(args.apps, man)
    todo, total, skipped = warmlib.plan_reads(files, args.max_bytes)

    before = sum(warmlib.resident(f)[0] for f in todo)
    start = time.monotonic()
    read = warmlib.warm(todo, args.workers)
    elapsed = time.monotonic() - start
    after = sum(warmlib.resident(f)[0] for f in todo)

    pct = (100.0 * after / total) if total else 0.0
    rate = (read / 2**20 / elapsed) if elapsed > 0 else 0.0
    print(
        f"store-preload: {len(todo)} files, {_mb(total)} in {elapsed:.2f}s "
        f"({rate:.0f} MB/s); resident {_mb(before)} -> {_mb(after)} ({pct:.1f}%)"
    )
    if skipped:
        print(f"store-preload: skipped {_mb(skipped)} to stay under the cap")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    man = manifest.prune(manifest.load(args.state))
    files = _ordered_files(args.apps, man)
    total = 0
    res = 0
    for f in files:
        r, s = warmlib.resident(f)
        res += r
        total += s
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
