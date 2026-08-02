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
# A reboot is now the whole router, not just the modem, and the box takes
# 60-90s to come back -- long enough that the window sized for a modem reset
# would report "timeout" while it was still booting normally.
REBOOT_TIMEOUT = 240.0
# One debug_at_info call now carries QENG, QCAINFO and CEREG together, so the
# three separate intervals they used to have collapse into this one.
#
# 30s is a deliberate compromise. Those commands used to be gated individually
# (QENG 30s, CEREG 60s, QCAINFO 10s), but debug_at_info is all-or-nothing --
# its signature is {bus, slot} with no command filter -- so every call runs all
# 32 AT commands the firmware puts in that batch. Keeping QCAINFO's old 10s
# would mean ~192 AT commands a minute against the ~9 we issue today. 30s costs
# some carrier-aggregation responsiveness and buys back registration freshness,
# at ~64/minute. Do not lower it without measuring what the modem does under
# that load.
DEBUG_AT_INTERVAL = 30.0
SIM_INTERVAL = 900.0  # the SIM's own name changes only on a SIM swap
# How soon to try again when a reading has never landed. Gating solely on
# "cache is empty" retries every 4s cycle forever on a router that cannot
# answer, which defeats the interval; gating solely on elapsed time makes a
# failed first read wait the full 900s before the operator name can appear.
SIM_RETRY = 30.0
# Battery level moves slowly and the MCU's warning thresholds are static
# config, so neither belongs on the 4s cycle. The web-RPC mirror already
# carries a percent every cycle; these two add cycle count, the abnormal flag
# and the thresholds.
MCU_INTERVAL = 60.0

# Last good raw QENG payload + when the batch that carries it last ran. Kept
# across cycles so a transient SSH/AT miss does not blank cellular.ca and
# flicker the widget. Latched per reading rather than per call: one command
# inside the batch can come back empty while the others are good.
_QENG_CACHE = None
_CEREG_CACHE = None
_QCAINFO_CACHE = None
_DEBUG_AT_LAST = 0.0

# The SIM's brand, straight from cellular.sim status -- no longer parsed out of
# AT+QSPN, which this modem answers with a bare OK because the SIM carries no
# SPN record.
_SIM_CACHE = None
_SIM_LAST = 0.0

_MCU_CACHE = None
_WARN_CACHE = None
_MCU_LAST = 0.0


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


def _parse_signals(out):
    """Interpret the get_signals payload from the batched session."""
    if not out:
        return None
    try:
        return (json.loads(out) or {}).get("signals")
    except (ValueError, json.JSONDecodeError):
        return None


# Every AT reading now arrives through cellular_manager's own debug_at_info,
# which runs the commands behind the lock held by the process that owns
# /dev/smd9. Writing to modem.CPU.AT ourselves -- which is what the four
# separate commands here used to do -- shares that channel with GL's gl_modem
# poller, and under contention the modem answers with CROSSED responses:
# another command's reply arriving for yours, indistinguishable from a real
# answer. One call now returns 32 AT results; we consume three of them.
_DEBUG_AT_CMD = ("ubus call cellular.network debug_at_info "
                 "'{\"bus\":\"cpu\",\"slot\":1}'")

# The SIM's brand. Replaces AT+QSPN entirely: this modem's SIM carries no SPN
# record and answered a bare OK, while cellular.sim status reports "Mint".
_SIM_STATUS_CMD = "ubus call cellular.sim status '{\"bus\":\"cpu\"}'"

# Keys into the debug_at_info result. These must match the firmware's `cmd`
# strings byte for byte -- including the inner quotes on QENG -- or the reading
# silently goes missing and the cache never refreshes.
#
# QENG: the camped serving cells, which populate even in RRC idle ("NOCONN"),
#   and the source of the registered PLMN.
# QCAINFO: the PCC plus every SCC -> the full carrier-aggregation view.
# CEREG: the EPS registration state, whose <stat> is the only authoritative
#   roaming signal (1 = home, 5 = roaming). Comparing PLMNs cannot answer this:
#   an MVNO rides its host's PLMN, so Mint on T-Mobile would read as roaming.
_AT_QENG = "AT+QENG=\"servingcell\""
_AT_QCAINFO = "AT+QCAINFO"
_AT_CEREG = "AT+CEREG?"




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
    global _QENG_CACHE, _QCAINFO_CACHE, _CEREG_CACHE, _DEBUG_AT_LAST
    global _SIM_CACHE, _SIM_LAST, _MCU_CACHE, _WARN_CACHE, _MCU_LAST

    steps = [("signals", "ubus call cellular.collect get_signals '{\"bus\":\"x\"}'"),
             # The uplink interface itself: how long since it dialled, plus the
             # lease it got. Every cycle -- it is a netifd status read and never
             # touches the modem.
             ("iface", "ubus call network.interface.modem_cpu status")]
    at_due = _DEBUG_AT_LAST == 0.0 or ts - _DEBUG_AT_LAST >= DEBUG_AT_INTERVAL
    if at_due:
        steps.append(("atinfo", _DEBUG_AT_CMD))
    sim_gap = SIM_INTERVAL if _SIM_CACHE else SIM_RETRY
    if _SIM_LAST == 0.0 or ts - _SIM_LAST >= sim_gap:
        steps.append(("simstatus", _SIM_STATUS_CMD))
    if _MCU_LAST == 0.0 or ts - _MCU_LAST >= MCU_INTERVAL:
        steps.append(("mcu", "ubus call mcu status"))
        steps.append(("mcuwarn", "ubus call mcu get_warning"))
    # NOT replaced by cellular.collect get_traffic. That method reports a single
    # combined `traffic_total` per slot, which would collapse the rx/tx split
    # the popup shows. /proc/net/dev is a plain file read and never touches the
    # AT channel, so there is nothing to gain by trading data away for it.
    steps.append(("netdev", "cat /proc/net/dev"))

    got, ssh_auth = _ssh_batch(steps)

    sig = _parse_signals(got.get("signals"))
    parts["signals"] = sig
    parts["iface"] = L.parse_iface_status(got.get("iface"))

    # Latch each reading on whether it PARSES, not on whether the response was
    # merely non-empty. The modem answers a bare "OK" often enough that a plain
    # truthiness check cached that as a good value and then refused to retry for
    # the whole interval -- which is what left sim_operator null.
    #
    # The three readings are latched independently even though they arrive in
    # one call: any single command inside the batch can come back empty or
    # ERROR while its neighbours are fine, and one bad line must not blank the
    # rest. A wholly failed call yields {} and latches nothing, so every cached
    # value survives exactly as it did when these were separate commands.
    if "atinfo" in got:
        _DEBUG_AT_LAST = ts
        at = L.parse_debug_at(got["atinfo"])

        _qeng_raw = at.get(_AT_QENG, "")
        if L.parse_qeng(_qeng_raw):
            _QENG_CACHE = _qeng_raw

        # QCAINFO keys on a PCC line rather than a parser: a valid PCC-only idle
        # read must be allowed through so the badge honestly drops when SCCs
        # deconfigure, while a total miss keeps the last value.
        _qcainfo_raw = at.get(_AT_QCAINFO, "")
        if '"PCC"' in _qcainfo_raw:
            _QCAINFO_CACHE = _qcainfo_raw

        _cereg_raw = at.get(_AT_CEREG, "")
        if L.parse_cereg(_cereg_raw):
            _CEREG_CACHE = _cereg_raw

    parts["qeng"] = _QENG_CACHE
    parts["qcainfo"] = _QCAINFO_CACHE
    parts["cereg"] = _CEREG_CACHE

    if "simstatus" in got:
        _SIM_LAST = ts
        _sim_name = L.parse_sim_carrier(got["simstatus"])
        if _sim_name:
            _SIM_CACHE = _sim_name
    parts["sim_operator"] = _SIM_CACHE

    # Latched like the AT readings: the thresholds and the status arrive in the
    # same window but from different calls, so one failing must not blank the
    # other's last good value.
    if "mcu" in got or "mcuwarn" in got:
        _MCU_LAST = ts
        _mcu = L.parse_mcu_status(got.get("mcu"))
        if _mcu:
            _MCU_CACHE = _mcu
        _warn = L.parse_mcu_warning(got.get("mcuwarn"))
        if _warn:
            _WARN_CACHE = _warn
    parts["mcu"] = _MCU_CACHE
    parts["mcu_warning"] = _WARN_CACHE

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
            budget = (REBOOT_TIMEOUT if marker.get("action") == "reboot"
                      else RECOVER_TIMEOUT)
            online_streak = 0
            while time.time() - started < budget:
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
