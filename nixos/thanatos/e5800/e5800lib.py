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


def _int_or_none(s):
    try:
        return int(s)
    except (TypeError, ValueError):
        return None


# MCC-MNC -> NETWORK name. Deliberately tiny: this exists because the modem
# will not name the registered network directly. AT+COPS? on this firmware
# answers a bare "+COPS: 5" with no <format>/<oper> fields, so the PLMN that
# QENG already reports (fetched every cycle for band info) is the only route.
#
# This is the network, NOT the subscriber's brand -- AT+QSPN carries that
# separately, and an MVNO like Mint shares its host's PLMN, which is exactly
# why a guess here would be wrong. An unknown PLMN falls back to its numeric
# form rather than guessing. Extend as needed.
PLMN_NAMES = {
    ("310", "260"): "T-Mobile",
    ("310", "410"): "AT&T",
    ("311", "480"): "Verizon",
    ("310", "120"): "Sprint",
    ("312", "530"): "Sprint",
    ("310", "030"): "AT&T",
    ("310", "150"): "AT&T",
    ("310", "170"): "AT&T",
    ("310", "200"): "T-Mobile",
    ("310", "210"): "T-Mobile",
    ("310", "220"): "T-Mobile",
    ("310", "230"): "T-Mobile",
    ("310", "240"): "T-Mobile",
    ("310", "250"): "T-Mobile",
    ("310", "270"): "T-Mobile",
    ("310", "310"): "T-Mobile",
    ("310", "660"): "T-Mobile",
    ("310", "800"): "T-Mobile",
    ("311", "660"): "Metro",
    ("312", "250"): "Verizon",
    ("302", "220"): "Telus",
    ("302", "610"): "Bell",
    ("302", "720"): "Rogers",
    ("334", "020"): "Telcel",
}


def fmt_plmn(mcc, mnc):
    """(mcc, mnc) -> "310-260", or None when either part is missing.

    MNC is kept as the modem reported it. Two- and three-digit MNCs are
    genuinely different networks (MNC 26 is not MNC 260), so this must not
    pad or strip digits.
    """
    if not mcc or not mnc:
        return None
    return "{}-{}".format(mcc, mnc)


def operator_from_plmn(mcc, mnc):
    """(mcc, mnc) -> operator name, falling back to the numeric PLMN.

    Returns None only when the PLMN itself is unknown. An unrecognised PLMN
    yields "310-260"-style text rather than None, because "which network" is
    still answered by the number -- and rather than a guess, because MVNOs
    share MCC/MNC with their host network and cannot be told apart here.
    """
    plmn = fmt_plmn(mcc, mnc)
    if plmn is None:
        return None
    return PLMN_NAMES.get((str(mcc), str(mnc)), plmn)


def parse_qspn(data):
    """Parse an AT+QSPN response into the SIM's service-provider name.

    Quectel answers `+QSPN: <FNN>,<SNN>,<SPN>,<alphabet>,<RPLMN>` where FNN is
    the full network name held on the SIM. This is where an MVNO carries its
    own brand: a Mint SIM reports "Mint" here while the network it rides is
    T-Mobile, which QENG reports as PLMN 310-260.

    Returns None when the SIM has no SPN record -- observed on this modem on
    2026-07-31, which answered a bare "OK" -- so the caller falls back to the
    network name rather than showing a blank.
    """
    if not data:
        return None
    for raw in str(data).splitlines():
        line = raw.strip()
        if not line.startswith("+QSPN:"):
            continue
        toks = [t.strip().strip('"') for t in line[len("+QSPN:"):].split(",")]
        for t in toks[:3]:  # FNN, then SNN, then SPN
            if t:
                return t
    return None


def operator_label(sim_name, network_name):
    """Compose the display name from the SIM's brand and the network's.

    "Mint (T-Mobile)" when they differ -- an MVNO subscriber is on Mint but
    riding T-Mobile, and both halves are worth knowing. Roaming makes the same
    shape useful: a Mint SIM on AT&T reads "Mint (AT&T)".

    Collapses to one name when they match, so a direct T-Mobile subscriber
    never sees "T-Mobile (T-Mobile)". Falls back to whichever half exists, and
    to None when neither does.
    """
    sim = (sim_name or "").strip()
    net = (network_name or "").strip()
    if sim and net and sim.lower() != net.lower():
        return "{} ({})".format(sim, net)
    return sim or net or None


def parse_qeng(data):
    """Parse an AT+QENG="servingcell" response into serving-cell band info.

    QENG reports the *camped* cells, so it works even in RRC idle ("NOCONN"),
    unlike QCAINFO/QNWINFO which only populate during an active data session.
    In the Quectel RG650V "servingcell" output the RAT name is the first token;
    the LTE band sits at token index 7 and the NR5G band at index 8 (0-based).

    Returns None when no serving cell is reported (idle-uncamped, No Service, or
    an empty/failed response), else:
        {"state": "NOCONN"|"CONNECT"|..., "mode": "NSA"|"SA"|"LTE"|None,
         "count": <int>, "bands": ["B2", "n41", ...],
         "cells": [{"rat": "LTE", "band": 2, "label": "B2"}, ...]}
    """
    if not data:
        return None
    state = None
    cells = []
    mcc = mnc = None
    for raw in str(data).splitlines():
        line = raw.strip()
        if not line.startswith("+QENG:"):
            continue
        toks = [t.strip().strip('"') for t in line[len("+QENG:"):].split(",")]
        head = toks[0] if toks else ""
        if head == "servingcell":
            state = toks[1] if len(toks) > 1 else None
        elif head == "LTE" and len(toks) > 7:
            # The registered PLMN sits right after the duplex mode. It is the
            # only place the operator is knowable at all -- see PLMN_NAMES.
            if mcc is None and len(toks) > 3:
                mcc, mnc = toks[2] or None, toks[3] or None
            b = _int_or_none(toks[7])
            if b is not None:
                cells.append({"rat": "LTE", "band": b, "label": "B" + str(b)})
        elif head.startswith("NR5G") and len(toks) > 8:
            # NR5G lines carry the PLMN one token earlier than LTE (no duplex
            # field). Only consulted when there is no LTE anchor line, so an
            # NSA reading reports the anchor's PLMN.
            if mcc is None and len(toks) > 2:
                mcc, mnc = toks[1] or None, toks[2] or None
            b = _int_or_none(toks[8])
            if b is not None:
                cells.append({"rat": head, "band": b, "label": "n" + str(b)})
    if not cells:
        return None
    rats = [c["rat"] for c in cells]
    if any("NSA" in r for r in rats):
        mode = "NSA"
    elif any(r.startswith("NR5G") for r in rats):
        mode = "SA"
    elif "LTE" in rats:
        mode = "LTE"
    else:
        mode = None
    return {
        "state": state,
        "mode": mode,
        "count": len(cells),
        "bands": [c["label"] for c in cells],
        "cells": cells,
        "plmn": fmt_plmn(mcc, mnc),
        "operator": operator_from_plmn(mcc, mnc),
    }


def _parse_ca_band(s):
    """QCAINFO band string -> (rat, band_int, label).

    "LTE BAND 66" -> ("LTE", 66, "B66"); "NR5G BAND 41" -> ("NR5G", 41, "n41").
    Returns (None, None, None) when unparseable.
    """
    parts = str(s).split()
    if len(parts) < 3:
        return (None, None, None)
    rat = parts[0]
    num = _int_or_none(parts[-1])
    if num is None:
        return (None, None, None)
    return (rat, num, ("B" if rat == "LTE" else "n") + str(num))


def parse_qcainfo(data):
    """Parse an AT+QCAINFO response into component-carrier aggregation info.

    QCAINFO enumerates the PCC and every SCC with a per-carrier activation
    state, so unlike QENG servingcell it sees all aggregated carriers (e.g. a
    second NR SCC). <scell_state>: 0=deconfigured, 1=configured-deactivated,
    2=configured-activated. The PCC line's state field is *registration* state
    (a different enum), so the PCC is always treated as the active primary. NR
    SCCs in EN-DC may appear in a short form ("SCC",freq,bw,band,PCID) with no
    state field; that is the serving NR PSCell and is treated as active.

    Returns None when no PCC line is present (idle / no service), else:
        {"mode": "NSA"|"SA"|"LTE"|None,
         "count": <configured carriers, state>=1>,
         "active_count": <activated carriers, state==2 / PCC / short-form>,
         "bands": [labels of configured carriers, report order],
         "carriers": [{"role","rat","band","label","state","active"}, ...]}
    (carriers includes deconfigured (state 0) carriers so the UI can dim them;
    count and bands exclude them.)
    """
    if not data:
        return None
    carriers = []
    configured_flags = []
    have_pcc = False
    for raw in str(data).splitlines():
        line = raw.strip()
        if not line.startswith("+QCAINFO:"):
            continue
        toks = [t.strip().strip('"')
                for t in line[len("+QCAINFO:"):].split(",")]
        role = toks[0] if toks else ""
        if role not in ("PCC", "SCC"):
            continue
        rat, band, label = _parse_ca_band(toks[3] if len(toks) > 3 else "")
        if band is None:
            continue
        if role == "PCC":
            have_pcc = True
            state, active, configured = None, True, True
        elif len(toks) <= 5:
            # NR short form (serving PSCell): no state field, treat as active.
            state, active, configured = None, True, True
        else:
            state = _int_or_none(toks[4])
            active = state == 2
            configured = state is not None and state >= 1
        carriers.append({"role": role, "rat": rat, "band": band,
                         "label": label, "state": state, "active": active})
        configured_flags.append(configured)
    if not have_pcc:
        return None
    configured = [c for c, f in zip(carriers, configured_flags) if f]
    pcc = next((c for c in carriers if c["role"] == "PCC"), None)
    rats = [c["rat"] for c in configured]
    if pcc and pcc["rat"] and pcc["rat"].startswith("NR5G"):
        mode = "SA"
    elif "LTE" in rats and any(r and r.startswith("NR5G") for r in rats):
        mode = "NSA"
    elif "LTE" in rats:
        mode = "LTE"
    else:
        mode = None
    return {
        "mode": mode,
        "count": len(configured),
        "active_count": sum(1 for c in carriers if c["active"]),
        "bands": [c["label"] for c in configured],
        "carriers": carriers,
    }


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
    serving = parse_qeng(parts.get("qeng"))
    sim_operator = parse_qspn(parts.get("qspn"))
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
            "ca": parse_qcainfo(parts.get("qcainfo")),
            "serving": serving,
            # Lifted out of `serving` so consumers do not have to know that the
            # operator arrives via a serving-cell band query. None when QENG did
            # not report a camped cell (idle-uncamped, No Service, or an SSH/AT
            # miss) -- the caller must render nothing, not "Unknown".
            # The NETWORK the modem is registered to, from the QENG PLMN.
            "operator": (serving or {}).get("operator"),
            "plmn": (serving or {}).get("plmn"),
            # The SIM's own brand, which differs from the network for an MVNO
            # (a Mint SIM rides T-Mobile). None when the SIM carries no SPN.
            "sim_operator": sim_operator,
            # What to display: "Mint (T-Mobile)" when they differ, one name
            # when they match, whichever exists when only one does.
            "operator_label": operator_label(sim_operator, (serving or {}).get("operator")),
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
