"""argparse entrypoint for affine-sync."""
import argparse, fcntl, os, sys
from . import config, engine

def _acquire_lock():
    # Cross-process mutex so a manual run and the Stop hook (or two hook runs)
    # can never sync concurrently -- concurrency races create duplicate folders.
    home = engine._home()
    try:
        os.makedirs(home, exist_ok=True)
        f = open(os.path.join(home, "sync.lock"), "w")
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return f            # hold the handle open to keep the lock
    except OSError:
        return None         # another affine-sync holds it -> skip this run

def main(argv=None):
    ap = argparse.ArgumentParser(prog="affine-sync")
    ap.add_argument("--file")
    ap.add_argument("--repo")
    ap.add_argument("--changed", action="store_true")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--readme", action="store_true")
    a = ap.parse_args(argv)
    try:
        cfg = config.load()
    except config.ConfigError as e:
        sys.stderr.write(str(e) + "\n")
        return 0                       # fail-soft: no config -> no-op
    lock = _acquire_lock()
    if lock is None:
        return 0                       # another sync is running -> skip (fail-soft)
    try:
        if a.file:
            repo_dir = a.repo or _git_top(os.path.dirname(os.path.abspath(a.file)))
            engine.sync_file(cfg, repo_dir, os.path.relpath(os.path.abspath(a.file), repo_dir))
        elif a.readme:
            c = engine._client(cfg)
            if c.reachable():
                engine.build_readme(cfg, c)
        elif a.repo and a.all:
            engine.sync_all(cfg, a.repo)
        elif a.repo:
            engine.sync_changed(cfg, a.repo)
    finally:
        lock.close()
    return 0

def _git_top(d):
    import subprocess
    r = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True)
    return r.stdout.strip() or d

if __name__ == "__main__":
    raise SystemExit(main())
