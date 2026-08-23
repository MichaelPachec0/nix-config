"""ff-firststart: what happens on the first firefox launch after the compositor.

  watch             sample system context until the launch under study is over
  snapshot <label>  profile state: locks, integrity, startup cache
  report [rundir]   correlate one boot's artifacts into a timeline

Artifacts land in $FF_FS_DIR/runs/<boot_id>/. Keyed by boot id because the
question is specifically about the first launch after a boot.
"""

from __future__ import annotations

import glob
import hashlib
import json
import os
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time

TICK_S = 0.25
# Stop this long after firefox is gone: the launch under study is over.
IDLE_STOP_S = 20.0

# Small state files worth hashing. A change between pre and post is the first
# thing to look at.
WATCH_FILES = [
    "compatibility.ini", "prefs.js", "times.json", "extensions.json",
    "addonStartup.json.lz4", "sessionstore-backups/recovery.jsonlz4",
    "sessionstore-backups/previous.jsonlz4",
]


def base_dir() -> str:
    d = os.environ.get("FF_FS_DIR")
    if d:
        return d
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(state, "ff-firststart")


def boot_id() -> str:
    with open("/proc/sys/kernel/random/boot_id") as f:
        return f.read().strip()


def run_dir() -> str:
    d = os.path.join(base_dir(), "runs", boot_id())
    os.makedirs(d, exist_ok=True)
    return d


def profile_dir() -> str:
    """The default profile per profiles.ini, or $FF_FS_PROFILE."""
    env = os.environ.get("FF_FS_PROFILE")
    if env:
        return env
    root = os.path.expanduser("~/.mozilla/firefox")
    ini = os.path.join(root, "profiles.ini")
    section: dict[str, str] = {}
    best = None
    try:
        with open(ini) as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    if section.get("Default") == "1" and "Path" in section:
                        best = section["Path"]
                    section = {}
                elif "=" in line:
                    k, v = line.split("=", 1)
                    section[k] = v
        if section.get("Default") == "1" and "Path" in section:
            best = section["Path"]
    except OSError:
        pass
    return os.path.join(root, best) if best else ""


def cache_dir(prof: str) -> str:
    return os.path.expanduser(
        f"~/.cache/mozilla/firefox/{os.path.basename(prof)}"
    )


def device_read_bytes() -> int:
    """Bytes read from real block devices since boot.

    Field 3 of /sys/block/*/stat (sectors read) x512, for devices with a
    `device` symlink. dm-*, loop* and zram0 are excluded: a read through
    dm-crypt appears identically on dm-2 and nvme0n1, so summing both would
    double count. mincore cannot answer this on /nix, it reports every page
    present unconditionally.
    """
    total = 0
    try:
        devs = os.listdir("/sys/block")
    except OSError:
        return 0
    for dev in devs:
        if not os.path.exists(f"/sys/block/{dev}/device"):
            continue
        try:
            with open(f"/sys/block/{dev}/stat") as f:
                total += int(f.read().split()[2]) * 512
        except (OSError, IndexError, ValueError):
            pass
    return total


def psi(resource: str) -> int:
    try:
        with open(f"/proc/pressure/{resource}") as f:
            for line in f:
                want = "some" if resource == "cpu" else "full"
                if line.startswith(want):
                    for tok in line.split():
                        if tok.startswith("total="):
                            return int(tok[6:])
    except OSError:
        pass
    return 0


def firefox_procs() -> tuple[int, int]:
    """(count, total rss kb) over all firefox processes. One /proc pass."""
    n = rss = 0
    try:
        entries = os.listdir("/proc")
    except OSError:
        return 0, 0
    for pid in entries:
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/comm") as f:
                if "firefox" not in f.read():
                    continue
            n += 1
            with open(f"/proc/{pid}/statm") as f:
                rss += int(f.read().split()[1]) * 4
        except (OSError, IndexError, ValueError):
            continue
    return n, rss


def unit_state(unit: str) -> str:
    try:
        out = subprocess.run(
            ["systemctl", "--user", "show", unit, "-p", "ActiveState",
             "-p", "SubState", "-p", "ExecMainStartTimestampMonotonic",
             "--value"],
            capture_output=True, text=True, timeout=5,
        )
        return "/".join(out.stdout.split())
    except (OSError, subprocess.SubprocessError):
        return "?"


def hypr_socket() -> str | None:
    """Newest Hyprland instance's event socket."""
    root = f"/run/user/{os.getuid()}/hypr"
    best, best_m = None, -1.0
    try:
        for d in os.listdir(root):
            p = f"{root}/{d}/.socket2.sock"
            if os.path.exists(p):
                m = os.path.getmtime(f"{root}/{d}")
                if m > best_m:
                    best, best_m = p, m
    except OSError:
        pass
    return best


def watch_windows(events: list, t0: float, stop: threading.Event) -> None:
    """Hyprland openwindow/closewindow events mentioning firefox.

    The event stream rather than polling hyprctl: this is a latency
    investigation and a fork every tick would be part of what it measures.
    """
    path = hypr_socket()
    if not path:
        return
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(1.0)
        s.connect(path)
    except OSError:
        return
    buf = b""
    while not stop.is_set():
        try:
            chunk = s.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            return
        if not chunk:
            return
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            text = line.decode("utf-8", "replace")
            if "firefox" in text.lower():
                events.append({"t": round(time.monotonic() - t0, 3),
                               "event": text})


def cmd_watch() -> int:
    deadline = float(os.environ.get("FF_FS_SECONDS", "900"))
    run = run_dir()
    t0 = time.monotonic()
    events: list = []
    stop = threading.Event()
    threading.Thread(target=watch_windows, args=(events, t0, stop),
                     daemon=True).start()

    dev0 = device_read_bytes()
    with open("/proc/uptime") as f:
        uptime = float(f.read().split()[0])
    with open(os.path.join(run, "session.meta"), "w") as f:
        json.dump({"start_epoch": time.time(), "uptime_s": uptime,
                   "boot_id": boot_id(), "dev_read_at_start": dev0}, f, indent=1)

    samples: list = []
    seen = False
    idle = 0.0
    while time.monotonic() - t0 < deadline:
        n, rss = firefox_procs()
        if n:
            seen, idle = True, 0.0
        elif seen:
            idle += TICK_S
        samples.append({
            "t": round(time.monotonic() - t0, 3),
            "ff_procs": n,
            "ff_rss_kb": rss,
            "dev_read_mb": round((device_read_bytes() - dev0) / 2**20, 1),
            "psi_io_us": psi("io"),
            "psi_cpu_us": psi("cpu"),
            "psi_mem_us": psi("memory"),
            "store_preload": unit_state("store-preload.service"),
            # Recorded so the sampler's own cost can be subtracted rather
            # than argued about.
            "self_cpu_s": round(sum(os.times()[:2]), 3),
        })
        if idle > IDLE_STOP_S:
            break
        time.sleep(TICK_S)

    stop.set()
    with open(os.path.join(run, "samples.json"), "w") as f:
        json.dump({"samples": samples, "window_events": events}, f, indent=1)
    print(f"ff-firststart: {len(samples)} samples, {len(events)} window events"
          f" -> {run}")
    return 0


def integrity(path: str, tmpdir: str) -> str:
    """PRAGMA integrity_check on an independent copy.

    reflink is disabled: a btrfs reflink shares extents with the live file
    rather than giving an independent copy. immutable=1 so this is safe while
    firefox holds the database.
    """
    dst = os.path.join(tmpdir, os.path.basename(path))
    try:
        subprocess.run(["cp", "--reflink=never", path, dst], check=True,
                       capture_output=True)
    except (subprocess.CalledProcessError, OSError) as e:
        return f"copy failed: {e}"
    try:
        c = sqlite3.connect(f"file:{dst}?mode=ro&immutable=1", uri=True)
        r: str = c.execute("PRAGMA integrity_check").fetchone()[0]
        c.close()
        return r
    except sqlite3.Error as e:
        # Some profile dbs declare collations only firefox registers
        # (suggest.sqlite -> geonames_collate). Unreadable here, not damaged.
        if "no such collation sequence" in str(e):
            return "skipped: custom collation"
        return f"ERROR {type(e).__name__}: {e}"
    finally:
        try:
            os.unlink(dst)
        except OSError:
            pass


def cmd_snapshot(label: str) -> int:
    prof = profile_dir()
    if not prof:
        print("ff-firststart: no default profile in profiles.ini")
        return 2
    run = run_dir()
    with open("/proc/uptime") as f:
        uptime = float(f.read().split()[0])
    out: dict = {"label": label, "epoch": time.time(), "uptime_s": uptime,
                 "profile": prof}

    lock = os.path.join(prof, "lock")
    out["lock"] = os.readlink(lock) if os.path.islink(lock) else None
    out["parentlock"] = os.path.exists(os.path.join(prof, ".parentlock"))

    files: dict = {}
    for rel in WATCH_FILES:
        p = os.path.join(prof, rel)
        try:
            st = os.stat(p)
            with open(p, "rb") as f:
                h = hashlib.sha256(f.read()).hexdigest()[:16]
            files[rel] = {"size": st.st_size, "mtime": round(st.st_mtime, 3),
                          "sha": h}
        except OSError:
            files[rel] = None
    out["files"] = files

    # Anything firefox judged damaged leaves a .corrupt sibling.
    out["corrupt_markers"] = sorted(
        os.path.basename(p) for p in
        glob.glob(f"{prof}/*.corrupt") + glob.glob(f"{prof}/corrupt*")
    )

    cache = os.path.expanduser("~/.cache")
    with tempfile.TemporaryDirectory(dir=cache) as tmp:
        out["integrity"] = {
            os.path.basename(db): integrity(db, tmp)
            for db in sorted(glob.glob(f"{prof}/*.sqlite"))
        }

    out["startup_cache"] = {
        os.path.basename(p): {"size": os.path.getsize(p),
                              "mtime": round(os.path.getmtime(p), 3)}
        for p in sorted(glob.glob(f"{cache_dir(prof)}/startupCache/*"))
    }

    path = os.path.join(run, f"snapshot-{label}.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)

    bad = [k for k, v in out["integrity"].items()
           if v != "ok" and not v.startswith("skipped")]
    markers = (", markers: " + ",".join(out["corrupt_markers"])
               if out["corrupt_markers"] else "")
    print(f"ff-firststart[{label}]: {len(out['integrity'])} dbs, "
          f"{'ALL OK' if not bad else 'BAD: ' + ', '.join(bad)}{markers}")
    return 0


def parse_meta(path: str) -> dict:
    d = {}
    with open(path) as f:
        for line in f:
            if "=" in line:
                k, v = line.rstrip("\n").split("=", 1)
                d[k] = v
    return d


def cmd_report(target: str | None) -> int:
    run = target or os.path.join(base_dir(), "runs", boot_id())
    if not os.path.isdir(run):
        print(f"no run dir: {run}")
        return 1
    print(f"=== {run} ===\n")

    metas = sorted(glob.glob(os.path.join(run, "launches", "*.meta")))
    if not metas:
        print("no launches recorded (shim inactive, or firefox not started)\n")
    for m in metas:
        d = parse_meta(m)
        log = m[:-5] + ".log"
        lived = "still running"
        if "end_epoch" in d and "start_epoch" in d:
            lived = f"{float(d['end_epoch']) - float(d['start_epoch']):.2f}s"
        print(f"-- launch {d.get('seq')}  uptime={d.get('uptime_s')}s  lived={lived}")
        print(f"   prior_instances : {d.get('prior_instances')}"
              f"   <- nonzero means this launch raced an existing firefox")
        print(f"   lock            : {d.get('lock_before')} -> {d.get('lock_after', '?')}")
        print(f"   recovery.jsonlz4: {d.get('recovery_before')} -> "
              f"{d.get('recovery_after', '?')}   <- present after = unclean exit")
        print(f"   store-preload   : {d.get('store_preload_ActiveState')}/"
              f"{d.get('store_preload_SubState')}"
              f"  ran={d.get('store_preload_ExecMainStartTimestamp')}")
        print(f"   mem available   : {int(d.get('mem_available_kb', 0)) // 1024} MB")
        # The shim sits on the launch path, so its cost is reported next to
        # what it measured rather than left for the reader to wonder about.
        ov = d.get("shim_overhead_us")
        if ov:
            print(f"   shim overhead   : {int(ov) / 1000:.1f} ms")
        size = os.path.getsize(log) if os.path.exists(log) else 0
        print(f"   stderr capture  : {size} bytes  {log}")
        if size:
            with open(log, errors="replace") as f:
                lines = [ln.rstrip() for ln in f]
            keep = [ln for ln in lines if any(
                w in ln.lower() for w in
                ("profile", "corrupt", "lock", "already running", "error",
                 "cannot", "fail", "damaged", "abort"))]
            for ln in (keep or lines)[:15]:
                print(f"     | {ln[:150]}")
        print()

    sp = os.path.join(run, "samples.json")
    if os.path.exists(sp):
        with open(sp) as f:
            data = json.load(f)
        s = data["samples"]
        print(f"-- watcher: {len(s)} samples over {s[-1]['t'] if s else 0}s")
        for e in data.get("window_events", [])[:10]:
            print(f"   window t={e['t']}s  {e['event'][:110]}")
        first = next((x for x in s if x["ff_procs"]), None)
        if first:
            peak = max(s, key=lambda x: x["ff_rss_kb"])
            print(f"   firefox first seen t={first['t']}s, "
                  f"dev_read={first['dev_read_mb']} MB")
            print(f"   peak rss {peak['ff_rss_kb'] // 1024} MB at t={peak['t']}s")
            print(f"   total dev read: {s[-1]['dev_read_mb']} MB")
            print(f"   sampler cpu: {s[-1]['self_cpu_s']}s")
        print()

    for snap in sorted(glob.glob(os.path.join(run, "snapshot-*.json"))):
        with open(snap) as f:
            d = json.load(f)
        bad = [k for k, v in d["integrity"].items()
               if v != "ok" and not v.startswith("skipped")]
        print(f"-- snapshot {d['label']} @ uptime {d['uptime_s']}s: "
              f"{'ALL OK' if not bad else 'BAD ' + ','.join(bad)}  "
              f"lock={d['lock']}  markers={d['corrupt_markers'] or 'none'}")
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    cmd = argv[0]
    if cmd == "watch":
        return cmd_watch()
    if cmd == "snapshot":
        return cmd_snapshot(argv[1] if len(argv) > 1 else "snap")
    if cmd == "report":
        return cmd_report(argv[1] if len(argv) > 1 else None)
    print(f"unknown command: {cmd}")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
