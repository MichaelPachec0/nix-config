#!/usr/bin/env python3
"""GL-E5800 poll loop: web-RPC dashboard + SSH cellular signal -> status.json.
Stdlib only. Secrets come from files named by env; never logged."""
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request

import e5800lib as L

HOST = os.environ.get("E5800_HOST", "http://192.168.8.1")
USER = os.environ.get("E5800_USER", "root")
WEB_PW_FILE = os.environ.get("E5800_WEB_PW_FILE", "")
SSH_KEY = os.environ.get("E5800_SSH_KEY", "")
RUNTIME = os.environ.get("E5800_RUNTIME", "/run/e5800")
STATE = os.environ.get("E5800_STATE", "/var/lib/e5800")
RESET_DAY = int(os.environ.get("E5800_RESET_DAY", "1"))
NETDEV = os.environ.get("E5800_NETDEV", "")
RPC = HOST.rstrip("/") + "/rpc"
HOSTPORT = (HOST.split("//")[-1].split("/")[0], 80)

WEB_INTERVAL = 4.0
SSH_INTERVAL = 20.0
RECOVER_INTERVAL = 2.0
RECOVER_TIMEOUT = 120.0


def _read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def _rpc(method, params, _id=1):
    body = json.dumps({"jsonrpc": "2.0", "id": _id,
                       "method": method, "params": params}).encode()
    req = urllib.request.Request(RPC, data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=6) as r:
        return json.loads(r.read())


def _login():
    pw = _read(WEB_PW_FILE)
    ch = _rpc("challenge", {"username": USER}).get("result", {})
    alg = {1: "-1", 5: "-5", 6: "-6"}.get(ch.get("alg", 1), "-1")
    p = subprocess.run(["openssl", "passwd", alg, "-salt", ch["salt"], "-stdin"],
                       input=pw.encode(), capture_output=True)
    cipher = p.stdout.decode().strip()
    h = L.login_hash(USER, cipher, ch["nonce"])
    return _rpc("login", {"username": USER, "hash": h})["result"]["sid"]


def _call(sid, svc, meth, args=None):
    return _rpc("call", [sid, svc, meth, args or {}]).get("result")


def _reachable():
    try:
        socket.create_connection(HOSTPORT, timeout=2).close()
        return True
    except OSError:
        return False


def _ssh(cmd):
    args = ["ssh", "-i", SSH_KEY, "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=5",
            "-o", "UserKnownHostsFile={}/known_hosts".format(STATE),
            "{}@{}".format(USER, HOSTPORT[0]), cmd]
    return subprocess.run(args, capture_output=True, timeout=15).stdout.decode()


def _signals():
    try:
        out = _ssh("ubus call cellular.collect get_signals '{\"bus\":\"x\"}'")
        return (json.loads(out) or {}).get("signals")
    except (subprocess.SubprocessError, ValueError, json.JSONDecodeError):
        return None


def _netdev_bytes():
    """Cumulative rx/tx bytes for the modem uplink netdev via /proc/net/dev on the router."""
    dev = NETDEV
    try:
        out = _ssh("cat /proc/net/dev")
        for line in out.splitlines():
            if ":" not in line:
                continue
            name, rest = line.split(":", 1)
            name = name.strip()
            if dev and name != dev:
                continue
            if not dev and not (name.startswith("rmnet") or name.startswith("wwan")
                                or name.startswith("modem")):
                continue
            f = rest.split()
            return int(f[0]), int(f[8])
    except (subprocess.SubprocessError, ValueError, IndexError):
        pass
    return None


def _load_state():
    try:
        with open(os.path.join(STATE, "usage.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _save_state(st):
    os.makedirs(STATE, exist_ok=True)
    tmp = os.path.join(STATE, "usage.json.tmp")
    with open(tmp, "w") as f:
        json.dump(st, f)
    os.replace(tmp, os.path.join(STATE, "usage.json"))


def _marker():
    try:
        with open(os.path.join(RUNTIME, "recovery.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _clear_marker(result):
    try:
        os.remove(os.path.join(RUNTIME, "recovery.json"))
    except OSError:
        pass


def _write(status):
    os.makedirs(RUNTIME, exist_ok=True)
    tmp = os.path.join(RUNTIME, "status.json.tmp")
    with open(tmp, "w") as f:
        json.dump(status, f)
    os.replace(tmp, os.path.join(RUNTIME, "status.json"))


def collect_once():
    """One full sample -> status dict. Static info fetched opportunistically."""
    ts = int(time.time())
    if not _reachable():
        return L.build_status({"ts": ts, "reachable": False})
    parts = {"ts": ts, "reachable": True, "carrier": "T-Mobile",
             "reset_day": RESET_DAY}
    try:
        sid = _login()
        parts["get_status"] = _call(sid, "system", "get_status")
        parts["get_speed"] = _call(sid, "clients", "get_speed")
        parts["get_list"] = _call(sid, "clients", "get_list")
        parts["vpn"] = _call(sid, "vpn-client", "get_status")
        parts["info"] = _call(sid, "system", "get_info")
        parts["plugged"] = bool((_call(sid, "lpm", "get_status") or {}).get("power_insert"))
    except (urllib.error.URLError, OSError, KeyError, ValueError):
        pass
    parts["signals"] = _signals()
    nb = _netdev_bytes()
    if nb is not None:
        st = L.usage_step(_load_state(), nb[0], nb[1], ts, RESET_DAY)
        _save_state(st)
        parts["usage"] = st
        parts["data_source"] = "counter"
    parts["recovery"] = _marker()
    return L.build_status(parts)


def loop():
    last_web = 0.0
    while True:
        marker = _marker()
        status = collect_once()
        _write(status)
        # Recovery constant-check + settle/timeout handling.
        if marker is not None:
            started = marker.get("started", int(time.time()))
            online_streak = 0
            while time.time() - started < RECOVER_TIMEOUT:
                time.sleep(RECOVER_INTERVAL)
                s = collect_once()
                _write(s)
                if s.get("uplink", {}).get("online") and (time.time() - started) > 8:
                    online_streak += 1
                    if online_streak >= 2:
                        _clear_marker("recovered")
                        break
                else:
                    online_streak = 0
            else:
                _clear_marker("timeout")
            continue
        time.sleep(WEB_INTERVAL)


def main():
    if "--once" in sys.argv:
        print(json.dumps(collect_once(), indent=2))
        return
    loop()


if __name__ == "__main__":
    main()
