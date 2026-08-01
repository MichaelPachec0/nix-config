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
# One batched session per cycle carries every command, so it needs more room
# than a single call did.
SSH_TIMEOUT = 45
RECOVER_INTERVAL = 2.0
RECOVER_TIMEOUT = 120.0
QENG_INTERVAL = 30.0  # serving-cell bands change slowly; refresh sparingly
QCAINFO_INTERVAL = 10.0  # SCC activation changes with traffic; refresh often
QSPN_INTERVAL = 900.0  # the SIM's own name changes only on a SIM swap
CEREG_INTERVAL = 60.0  # registration state changes on cell reselect, not per cycle

# Last good raw QENG payload + when it was last fetched. Kept across cycles so a
# transient SSH/AT miss does not blank cellular.ca and flicker the widget.
_QENG_CACHE = None
_QENG_LAST = 0.0
_QSPN_CACHE = None
_QSPN_LAST = 0.0
_CEREG_CACHE = None
_CEREG_LAST = 0.0

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
        p = subprocess.run(args, capture_output=True, timeout=SSH_TIMEOUT)
        return p.stdout.decode(), p.returncode
    except subprocess.SubprocessError:
        return "", 255


# Marker framing for the batched session below. Chosen to be impossible in ubus
# JSON, AT responses or /proc/net/dev output, so a payload can never forge one.
_MARK = "@@e5800:{}@@"


def _ssh_batch(steps):
    """Run several remote commands over ONE ssh connection, in order.

    steps: [(name, remote_command)] -> ({name: stdout}, ssh_auth_failed)

    One connection rather than one per command: every extra connect pays a full
    SSH handshake against a router whose sshd is slow under load, and the AT
    passthrough commands share a single modem channel that answers better when
    they are issued back to back in one session than across reconnects.

    Commands run synchronously and in the given order -- the remote shell moves
    to the next only after the previous exits -- so AT calls never overlap.
    Output is framed by markers rather than split by position, because any
    single command may print nothing at all.

    A command that fails does not abort the rest: each is followed by `|| true`
    so one missing binary or a busy modem cannot blank every other reading.
    """
    if not steps:
        return {}, False
    script = []
    for name, cmd in steps:
        script.append("printf '\\n%s\\n'" % _MARK.format(name))
        script.append("{ %s ; } 2>/dev/null || true" % cmd)
    script.append("printf '\\n%s\\n'" % _MARK.format("end"))
    out, rc = _ssh("; ".join(script))
    if rc == 255:
        return {}, True
    result = {}
    names = [n for n, _ in steps] + ["end"]
    # Walk the markers in order; anything between one marker and the next
    # belongs to that command.
    pos = {}
    for n in names:
        idx = out.find(_MARK.format(n))
        if idx >= 0:
            pos[n] = idx
    ordered = [(pos[n], n) for n in names if n in pos]
    ordered.sort()
    for i, (idx, n) in enumerate(ordered):
        if n == "end":
            continue
        start = idx + len(_MARK.format(n))
        stop = ordered[i + 1][0] if i + 1 < len(ordered) else len(out)
        result[n] = out[start:stop].strip()
    return result, False


def _at_data(out):
    """Unwrap a modem.CPU.AT response into its raw AT text.

    The passthrough answers {"data": "<raw AT>", "channel_status": true}; the
    AT text carries real CRLFs only AFTER json decoding, so every parser must
    be handed `.data` rather than the envelope. Returns "" when the call failed
    or returned nothing.
    """
    if not out:
        return ""
    try:
        return (json.loads(out) or {}).get("data") or ""
    except (ValueError, json.JSONDecodeError):
        return ""


def _parse_signals(out):
    """Interpret the get_signals payload from the batched session."""
    if not out:
        return None
    try:
        return (json.loads(out) or {}).get("signals")
    except (ValueError, json.JSONDecodeError):
        return None


# AT+QENG="servingcell" via the modem AT passthrough. The inner quotes around
# servingcell must survive the JSON string (\") and the remote shell's single
# quotes, hence the double-escaping. get_result_AT returns {"data": <raw AT>}.
_QENG_CMD = ("ubus call modem.CPU.AT get_result_AT "
             "'{\"cmd\":\"AT+QENG=\\\"servingcell\\\"\","
             "\"timeout\":5,\"source_flag\":0,\"sub_id\":0}'")




# AT+QCAINFO via the modem AT passthrough (same channel/escaping as QENG). Lists
# the PCC + every SCC with activation state -> the full carrier-aggregation view.
_QCAINFO_CMD = ("ubus call modem.CPU.AT get_result_AT "
                "'{\"cmd\":\"AT+QCAINFO\",\"timeout\":5,"
                "\"source_flag\":0,\"sub_id\":0}'")




# AT+QSPN via the modem AT passthrough (same channel/escaping as QENG). Reads
# the Service Provider Name off the SIM, which is where an MVNO carries its own
# brand: a Mint SIM on T-Mobile's network reports "Mint" here and "310-260"
# (T-Mobile) through QENG. Firmware with no SPN record on the SIM answers a
# bare OK, which parse_qspn renders as None -- see the note there.
_QSPN_CMD = ("ubus call modem.CPU.AT get_result_AT "
             "'{\"cmd\":\"AT+QSPN\",\"timeout\":5,"
             "\"source_flag\":0,\"sub_id\":0}'")




# AT+CEREG? via the modem AT passthrough (same channel/escaping as QENG). The
# EPS registration state, whose <stat> is the only authoritative roaming signal:
# 1 = registered on the home network, 5 = registered while roaming. Comparing
# PLMNs cannot answer this -- an MVNO rides its host's PLMN, so Mint on T-Mobile
# would look like roaming, and a national roaming agreement can share one.
_CEREG_CMD = ("ubus call modem.CPU.AT get_result_AT "
              "'{\"cmd\":\"AT+CEREG?\",\"timeout\":5,"
              "\"source_flag\":0,\"sub_id\":0}'")




def _parse_netdev(out):
    """Cumulative (rx, tx) for the modem uplink netdev, from /proc/net/dev text
    supplied by the batched session. None when the device is absent."""
    if not out:
        return None
    dev = NETDEV
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
            return (int(f[0]), int(f[8]))
    except (ValueError, IndexError):
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
    # No hardcoded carrier: device.carrier is derived from the SIM and the
    # registered network in build_status. A literal here read "T-Mobile" on any
    # SIM and while roaming on anyone else's network.
    parts = {"ts": ts, "reachable": True, "reset_day": RESET_DAY}
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
    # ONE ssh session per cycle carries every remote read. Each of these used to
    # open its own connection -- six per cycle -- paying a full SSH handshake
    # each time against a router whose sshd is slow under load, and issuing the
    # AT passthrough calls across separate sessions rather than back to back on
    # one channel. They run synchronously and in this order; the remote shell
    # starts each only after the previous exits, so AT calls never overlap.
    #
    # Interval gating still applies, but only to decide what goes INTO the
    # batch: QSPN changes on a SIM swap and QCAINFO with traffic, so there is
    # no reason to ask for both every cycle even when they are free to carry.
    global _QENG_CACHE, _QENG_LAST, _QCAINFO_CACHE, _QCAINFO_LAST
    global _QSPN_CACHE, _QSPN_LAST, _CEREG_CACHE, _CEREG_LAST

    steps = [("signals", "ubus call cellular.collect get_signals '{\"bus\":\"x\"}'")]
    at_due = []
    if _QENG_CACHE is None or ts - _QENG_LAST >= QENG_INTERVAL:
        at_due.append(("qeng", _QENG_CMD))
    if _QCAINFO_CACHE is None or ts - _QCAINFO_LAST >= QCAINFO_INTERVAL:
        at_due.append(("qcainfo", _QCAINFO_CMD))
    if _QSPN_CACHE is None or ts - _QSPN_LAST >= QSPN_INTERVAL:
        at_due.append(("qspn", _QSPN_CMD))
    if _CEREG_CACHE is None or ts - _CEREG_LAST >= CEREG_INTERVAL:
        at_due.append(("cereg", _CEREG_CMD))
    steps.extend(at_due)
    steps.append(("netdev", "cat /proc/net/dev"))

    got, ssh_auth = _ssh_batch(steps)

    sig = _parse_signals(got.get("signals"))
    parts["signals"] = sig

    # Latch every AT reading on whether it PARSES, not on whether the response
    # was merely non-empty. The modem answers a bare "OK" often enough that a
    # plain truthiness check cached that as a good value and then refused to
    # retry for the whole interval -- which is what left sim_operator null.
    if "qeng" in got:
        _QENG_LAST = ts
        _qeng_raw = _at_data(got["qeng"])
        if L.parse_qeng(_qeng_raw):
            _QENG_CACHE = _qeng_raw
    parts["qeng"] = _QENG_CACHE

    # QCAINFO keys on a PCC line rather than a parser: a valid PCC-only idle
    # read must be allowed through so the badge honestly drops when SCCs
    # deconfigure, while a total miss keeps the last value.
    if "qcainfo" in got:
        _QCAINFO_LAST = ts
        _qcainfo_raw = _at_data(got["qcainfo"])
        if '"PCC"' in _qcainfo_raw:
            _QCAINFO_CACHE = _qcainfo_raw
    parts["qcainfo"] = _QCAINFO_CACHE

    if "qspn" in got:
        _QSPN_LAST = ts
        _qspn_raw = _at_data(got["qspn"])
        if L.parse_qspn(_qspn_raw):
            _QSPN_CACHE = _qspn_raw
    parts["qspn"] = _QSPN_CACHE

    if "cereg" in got:
        _CEREG_LAST = ts
        _cereg_raw = _at_data(got["cereg"])
        if L.parse_cereg(_cereg_raw):
            _CEREG_CACHE = _cereg_raw
    parts["cereg"] = _CEREG_CACHE

    nb = _parse_netdev(got.get("netdev"))
    if nb is not None:
        st = L.usage_step(_load_state(), nb[0], nb[1], ts, RESET_DAY)
        _save_state(st)
        parts["usage"] = st
        parts["data_source"] = "counter"
    # Reachable at the network layer but SSH rejected (exit 255) => the key no
    # longer works (e.g. router was factory-reset). Surface it so the widget can
    # prompt re-authentication.
    parts["auth_error"] = bool(ssh_auth)
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
