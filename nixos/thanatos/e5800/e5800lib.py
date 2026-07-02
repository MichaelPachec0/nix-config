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
