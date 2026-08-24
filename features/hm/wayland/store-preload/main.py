"""store-preload: warm the store working set of a few apps at session start.

  seed    print what the resolver derives per app
  record  merge currently-mapped files into the manifest
  warm    read seed + manifest into page cache, report bytes actually off disk
  status  report manifest size; residency is not measurable without reading
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import time

import manifest
import record
import warm as warmlib

DEFAULT_APPS = ["rofi", "kitty", "quickshell", "firefox-devedition"]
DEFAULT_WORKERS = 4
DEFAULT_MAX_BYTES = 2 << 30

STORE_ROOT_RE = re.compile(r"/nix/store/[0-9a-df-np-sv-z]{32}-[^/]+")

# warmApps keys (Task 3) are kitty/rofi/quickshell/firefox, and the seed
# files under seedDir are named after those keys. But --apps and the
# manifest use the RUNTIME app name, where firefox is packaged as
# firefox-devedition. Route explicitly rather than renaming either side.
SEED_KEY = {"firefox-devedition": "firefox"}


def _seed_key(app: str) -> str:
    """The seed file's name for a runtime app name."""
    return SEED_KEY.get(app, app)


def load_seed(seed_dir: str, app: str) -> list[str]:
    """The build-time seed for app. Missing is empty, not an error."""
    try:
        with open(os.path.join(seed_dir, app), encoding="utf-8") as f:
            return [ln.strip() for ln in f if ln.strip()]
    except OSError:
        return []


def seed_stamp(seed_dir: str, app: str) -> str | None:
    """Generation stamp: the store root of the seed's first line.

    That line is the real binary. Replaces store_root(real_binary(app)), which
    needed a PATH lookup and returned None under the unit's PATH, which is why
    the stamp was inert and every manifest entry carried root="".
    """
    files = load_seed(seed_dir, app)
    if not files:
        return None
    m = STORE_ROOT_RE.match(files[0])
    return m.group(0) if m else None


def _state_path() -> str:
    """Manifest path under XDG_STATE_HOME.

    /home is a separate btrfs fs and survives the stage-1 root rollback, so
    no /persist entry is needed.
    """
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "store-preload", "manifest.json")


def _mb(n: int) -> str:
    return f"{n / 2**20:.1f} MB"


def _ordered_files(
    apps: list[str], man: manifest.Manifest, seed_dir: str
) -> list[str]:
    """Union of seed and manifest, in app order, deduped.

    First app is warmed first. Put what you wait on at the top.
    """
    seen: set[str] = set()
    out: list[str] = []
    for app in apps:
        for path in load_seed(seed_dir, _seed_key(app)) + list(man.get(app, [])):
            if path not in seen:
                seen.add(path)
                out.append(path)
    return out


def _from_root(files: list[str], root: str) -> bool:
    """True if any file lives under root."""
    return any(f.startswith(root + "/") for f in files)


def cmd_seed(args: argparse.Namespace) -> int:
    for app in args.apps:
        files = load_seed(args.seed_dir, _seed_key(app))
        size = sum(os.path.getsize(f) for f in files if os.path.exists(f))
        print(f"{app:12} {len(files):5d} files  {_mb(size)}")
    return 0


def cmd_record(args: argparse.Namespace) -> int:
    path = args.state
    was_man = manifest.load(path)
    was_roots = manifest.load_roots(path)
    # restrict before prune: no point stat'ing the paths of a dropped app.
    man = manifest.prune(manifest.restrict(was_man, args.apps))
    roots = {a: r for a, r in was_roots.items() if a in args.apps}

    found = record.scan(args.apps)
    reset: list[str] = []
    for app, files in sorted(found.items()):
        # An app's store root is its generation stamp. Retained generations
        # keep the old closure on disk, so prune cannot see a rebuild.
        stamp = seed_stamp(args.seed_dir, _seed_key(app))
        was = roots.get(app)
        # Reset only if the scan corroborates the stamp. After a rebuild PATH
        # points at the new generation while the running process still maps the
        # old one; stamping those old paths as new would hide them forever.
        # Leaving the stale root fires the check again once the app restarts.
        if stamp is not None and was != stamp and _from_root(files, stamp):
            man = manifest.replace(man, app, files)
            roots[app] = stamp
            if was is not None:
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

    if args.dry_run:
        # Seed-key namespace (matches cfg.packages / seedDir file names, e.g.
        # "firefox" not "firefox-devedition"): the build-time guard iterates
        # cfg.packages, so the label here has to be what that loop expects.
        for app in args.apps:
            files = _ordered_files([app], man, args.seed_dir)
            total = sum(os.path.getsize(f) for f in files if os.path.exists(f))
            print(f"{_seed_key(app)} {total}")
        return 0

    files = _ordered_files(args.apps, man, args.seed_dir)
    todo, planned, skipped = warmlib.plan_reads(files, args.max_bytes)

    if not planned:
        # A warm that plans nothing is the bug this module shipped with. It
        # must fail loudly, not report success on an empty set.
        print("store-preload: planned 0 bytes, refusing", file=sys.stderr)
        return 1

    # mincore is not usable here: it reports 100% resident for every /nix
    # file unconditionally. device_read_bytes() is the oracle instead --
    # bytes that actually left the disk, measured across the whole pass.
    dev_before = warmlib.device_read_bytes()
    start = time.monotonic()
    read = warmlib.warm(todo, args.workers)
    elapsed = time.monotonic() - start
    dev_after = warmlib.device_read_bytes()

    off_disk = max(0, dev_after - dev_before)
    cold_pct = (100.0 * off_disk / read) if read else 0.0
    rate = (read / 2**20 / elapsed) if elapsed > 0 else 0.0
    print(
        f"store-preload: {len(todo)} files, {_mb(planned)} in {elapsed:.2f}s "
        f"({rate:.0f} MB/s); {_mb(off_disk)} off disk ({cold_pct:.1f}% was cold)"
    )
    if skipped:
        print(f"store-preload: skipped {_mb(skipped)} to stay under the cap")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    man = manifest.prune(manifest.load(args.state))
    files = _ordered_files(args.apps, man, args.seed_dir)
    total = sum(os.path.getsize(f) for f in files if os.path.exists(f))
    print(f"store-preload: {len(files)} files, {_mb(total)}")
    print(
        "store-preload: residency cannot be measured without reading; "
        "run `warm` for what was actually cold"
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
    parser.add_argument("--seed-dir", required=True)
    parser.add_argument("--dry-run", action="store_true")
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
