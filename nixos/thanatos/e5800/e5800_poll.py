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
QENG_INTERVAL = 30.0  # serving-cell bands change slowly; refresh sparingly
QCAINFO_INTERVAL = 10.0  # SCC activation changes with traffic; refresh often

# Last good raw QENG payload + when it was last fetched. Kept across cycles so a
# transient SSH/AT miss does not blank cellular.ca and flicker the widget.
_QENG_CACHE = None
_QENG_LAST = 0.0

# Last good raw QCAINFO payload + fetch time, latched like QENG so a transient
# SSH/AT miss does not blank cellular.ca.
_QCAINFO_CACHE = None
_QCAINFO_LAST = 0.0


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
    """Run a command on the router over SSH. Returns (stdout, returncode).
    Host keys are verified (TOFU): the first connect pins the router's key into
    the persistent known_hosts; later mismatches (rejected key OR a factory
    reset's new host key) make ssh exit 255, which we surface as auth_error so
    the widget can prompt re-authentication (re-add the key + clear known_hosts).

    -F /dev/null makes ssh ignore the system /etc/ssh/ssh_config. NixOS's gpg-agent
    SSH support installs a `Match host * exec "gpg-connect-agent ..."` hook there,
    which openssh runs via the calling user's login shell. e5800poll's shell is
    nologin, so without this every connect would spawn nologin and spam the journal
    ("Attempted login by UNKNOWN (UID: 980)"). We pass every option we need via -o,
    so ignoring the system config loses nothing."""
    args = ["ssh", "-F", "/dev/null", "-i", SSH_KEY, "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile={}/known_hosts".format(STATE),
            "-o", "ConnectTimeout=5",
            "{}@{}".format(USER, HOSTPORT[0]), cmd]
    try:
        p = subprocess.run(args, capture_output=True, timeout=15)
        return p.stdout.decode(), p.returncode
    except subprocess.SubprocessError:
        return "", 255


def _signals():
    """Returns (signals_list_or_None, ssh_auth_failed)."""
    out, rc = _ssh("ubus call cellular.collect get_signals '{\"bus\":\"x\"}'")
    if rc == 255:
        return None, True
    try:
        return (json.loads(out) or {}).get("signals"), False
    except (ValueError, json.JSONDecodeError):
        return None, False


# AT+QENG="servingcell" via the modem AT passthrough. The inner quotes around
# servingcell must survive the JSON string (\") and the remote shell's single
# quotes, hence the double-escaping. get_result_AT returns {"data": <raw AT>}.
_QENG_CMD = ("ubus call modem.CPU.AT get_result_AT "
             "'{\"cmd\":\"AT+QENG=\\\"servingcell\\\"\","
             "\"timeout\":5,\"source_flag\":0,\"sub_id\":0}'")


def _qeng():
    """Camped serving-cell bands via AT passthrough (populates even in RRC
    idle, unlike QCAINFO/QNWINFO). Returns (raw_at_data_or_None, ssh_auth)."""
    out, rc = _ssh(_QENG_CMD)
    if rc == 255:
        return None, True
    try:
        return (json.loads(out) or {}).get("data"), False
    except (ValueError, json.JSONDecodeError):
        return None, False


# AT+QCAINFO via the modem AT passthrough (same channel/escaping as QENG). Lists
# the PCC + every SCC with activation state -> the full carrier-aggregation view.
_QCAINFO_CMD = ("ubus call modem.CPU.AT get_result_AT "
                "'{\"cmd\":\"AT+QCAINFO\",\"timeout\":5,"
                "\"source_flag\":0,\"sub_id\":0}'")


def _qcainfo():
    """Component-carrier aggregation via AT passthrough.
    Returns (raw_at_data_or_None, ssh_auth)."""
    out, rc = _ssh(_QCAINFO_CMD)
    if rc == 255:
        return None, True
    try:
        return (json.loads(out) or {}).get("data"), False
    except (ValueError, json.JSONDecodeError):
        return None, False


def _netdev_bytes():
    """Cumulative rx/tx bytes for the modem uplink netdev via /proc/net/dev on the
    router. Returns ((rx, tx) or None, ssh_auth_failed)."""
    dev = NETDEV
    out, rc = _ssh("cat /proc/net/dev")
    if rc == 255:
        return None, True
    try:
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
            return (int(f[0]), int(f[8])), False
    except (ValueError, IndexError):
        pass
    return None, False


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
    sig, sig_auth = _signals()
    parts["signals"] = sig
    # Refresh the serving-cell bands sparingly and latch the last good value:
    # QENG shares the modem AT channel and the router's SSH is flaky under load,
    # so a per-cycle fetch flickers cellular.ca. Retry every cycle only until the
    # first success, then throttle; never overwrite a good value with a miss.
    global _QENG_CACHE, _QENG_LAST
    qeng_auth = False
    if not sig_auth and (_QENG_CACHE is None or ts - _QENG_LAST >= QENG_INTERVAL):
        raw, qeng_auth = _qeng()
        _QENG_LAST = ts
        if raw:
            _QENG_CACHE = raw
    parts["qeng"] = _QENG_CACHE
    # QCAINFO carries the full aggregation (PCC + all SCCs with activation
    # state). Latch like QENG but keyed on a PCC line: a total SSH/AT miss keeps
    # the last value (no blank), while a valid PCC-only idle read is allowed
    # through so the badge honestly drops when SCCs deconfigure (track-real-state).
    global _QCAINFO_CACHE, _QCAINFO_LAST
    qcainfo_auth = False
    if not sig_auth and (_QCAINFO_CACHE is None
                         or ts - _QCAINFO_LAST >= QCAINFO_INTERVAL):
        raw, qcainfo_auth = _qcainfo()
        _QCAINFO_LAST = ts
        if raw and '"PCC"' in raw:
            _QCAINFO_CACHE = raw
    parts["qcainfo"] = _QCAINFO_CACHE
    nb, nb_auth = _netdev_bytes()
    if nb is not None:
        st = L.usage_step(_load_state(), nb[0], nb[1], ts, RESET_DAY)
        _save_state(st)
        parts["usage"] = st
        parts["data_source"] = "counter"
    # Reachable at the network layer but SSH rejected (exit 255) => the key no
    # longer works (e.g. router was factory-reset). Surface it so the widget can
    # prompt re-authentication.
    parts["auth_error"] = bool(sig_auth or nb_auth or qeng_auth or qcainfo_auth)
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
