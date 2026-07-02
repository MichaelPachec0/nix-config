"""Pure logic for the GL-E5800 poll service. Stdlib only, no I/O -- unit-tested."""
import hashlib
import datetime


def login_hash(user, cipher, nonce):
    """GL.iNet 4.x web-RPC login hash: sha256hex(user:cipher:nonce)."""
    return hashlib.sha256(
        "{}:{}:{}".format(user, cipher, nonce).encode()).hexdigest()


def gen_from_network_type(nt):
    """Map a modem network_type string to a coarse generation label."""
    s = (nt or "").upper()
    if s.startswith("NR5G") or "5G" in s:
        return "5G"
    if "LTE" in s:
        return "4G"
    if "WCDMA" in s or "UMTS" in s or "HSPA" in s or "3G" in s:
        return "3G"
    if "GSM" in s or "EDGE" in s or "2G" in s:
        return "2G"
    return "?"


def cycle_anchor(now_ts, reset_day):
    """Unix ts of the most recent reset-day 00:00 UTC at or before now_ts."""
    now = datetime.datetime.fromtimestamp(now_ts, datetime.timezone.utc)
    day = min(reset_day, 28)  # keep valid in every month
    anchor = now.replace(day=day, hour=0, minute=0, second=0, microsecond=0)
    if anchor > now:
        # roll back one month
        year = now.year - 1 if now.month == 1 else now.year
        month = 12 if now.month == 1 else now.month - 1
        anchor = anchor.replace(year=year, month=month)
    return int(anchor.timestamp())


def usage_step(state, cur_rx, cur_tx, now_ts, reset_day):
    """Advance the persistent plan-cycle usage counter by one sample."""
    anchor = cycle_anchor(now_ts, reset_day)
    cycle_rx = state.get("cycle_rx", 0)
    cycle_tx = state.get("cycle_tx", 0)
    cycle_start = state.get("cycle_start")
    have_last = "last_rx" in state
    last_rx = state.get("last_rx", 0)
    last_tx = state.get("last_tx", 0)

    if cycle_start is None or cycle_start < anchor:
        # New billing cycle: zero the totals and restart the delta baseline.
        cycle_rx = 0
        cycle_tx = 0
        cycle_start = anchor
        have_last = False

    if not have_last:
        d_rx, d_tx = cur_rx, cur_tx
    else:
        d_rx = cur_rx if cur_rx < last_rx else cur_rx - last_rx
        d_tx = cur_tx if cur_tx < last_tx else cur_tx - last_tx

    return {
        "cycle_rx": cycle_rx + d_rx,
        "cycle_tx": cycle_tx + d_tx,
        "cycle_start": cycle_start,
        "last_rx": cur_rx,
        "last_tx": cur_tx,
    }


def _active_uplink(networks):
    nets = networks or []
    for n in nets:
        if n.get("online"):
            return n
    for n in nets:
        if n.get("up"):
            return n
    return nets[0] if nets else {}


def build_status(parts):
    ts = parts.get("ts", 0)
    if not parts.get("reachable"):
        return {"schema": 1, "ts": ts, "reachable": False}

    gs = parts.get("get_status") or {}
    sysd = gs.get("system") or {}
    mcu = sysd.get("mcu") or {}
    client = (gs.get("client") or [{}])[0]
    up = _active_uplink(gs.get("network"))
    speed = parts.get("get_speed") or {}
    info = parts.get("info") or {}
    sig_list = parts.get("signals")
    sig = (sig_list or [{}])[0] if sig_list else {}
    usage = parts.get("usage") or {}
    marker = parts.get("recovery")
    vpn_list = (parts.get("vpn") or {}).get("status_list") or []
    vpn_active = next((v for v in vpn_list if v.get("enabled")), None)

    return {
        "schema": 1,
        "ts": ts,
        "reachable": True,
        "auth_error": bool(parts.get("auth_error", False)),
        "device": {
            "model": "GL-" + str(info.get("model", "E5800")).upper().replace("GL-", ""),
            "firmware": info.get("firmware_version", ""),
            "modem": info.get("modem", "Quectel RG650V-NA"),
            "carrier": parts.get("carrier", ""),
        },
        "battery": {
            "percent": mcu.get("charge_percent"),
            "charging": bool(mcu.get("charging_status")),
            "plugged": bool(parts.get("plugged")),
            "fastcharge": bool(mcu.get("fastcharge")),
            "temp": mcu.get("temperature"),
        },
        "uplink": {
            "interface": up.get("interface"),
            "online": bool(up.get("online")),
            "up": bool(up.get("up")),
        },
        "recovery": {
            "active": marker is not None,
            "action": (marker or {}).get("action"),
            "started": (marker or {}).get("started"),
            "result": (marker or {}).get("result"),
        },
        "cellular": {
            "supported": bool(sig_list),
            "gen": gen_from_network_type(sig.get("network_type")),
            "network_type": sig.get("network_type"),
            "strength": sig.get("strength"),
            "rsrp": sig.get("rsrp"),
            "rsrq": sig.get("rsrq"),
            "sinr": sig.get("sinr"),
            "slot": sig.get("slot"),
        },
        "throughput": {
            "rx": speed.get("speed_rx"),
            "tx": speed.get("speed_tx"),
            "unit": parts.get("speed_unit", "Bps"),
        },
        "data": {
            "cycle_rx": usage.get("cycle_rx"),
            "cycle_tx": usage.get("cycle_tx"),
            "cycle_start": usage.get("cycle_start"),
            "reset_day": parts.get("reset_day", 1),
            "source": parts.get("data_source", "counter"),
        },
        "system": {
            "cpu_temp": (sysd.get("cpu") or {}).get("temperature"),
            "load": sysd.get("load_average", []),
            "mem_total": sysd.get("memory_total"),
            "mem_free": sysd.get("memory_free"),
            "mem_buff": sysd.get("memory_buff_cache"),
            "flash_total": sysd.get("flash_total"),
            "flash_free": sysd.get("flash_free"),
            "uptime": sysd.get("uptime"),
        },
        "clients": {
            "wireless": client.get("wireless_total", 0),
            "cable": client.get("cable_total", 0),
            "usbeth": client.get("usbeth_total", 0),
            "list": [
                {"name": c.get("name"), "ip": c.get("ip"),
                 "online": bool(c.get("online")),
                 "rx": c.get("rx"), "tx": c.get("tx")}
                for c in ((parts.get("get_list") or {}).get("clients") or [])
            ],
        },
        "wifi": [
            {"band": w.get("band"), "ssid": w.get("ssid"),
             "up": bool(w.get("up")), "guest": bool(w.get("guest"))}
            for w in (gs.get("wifi") or [])
        ],
        "vpn": {
            "active": vpn_active is not None,
            "name": (vpn_active or {}).get("name"),
            "type": (vpn_active or {}).get("type"),
        },
    }
