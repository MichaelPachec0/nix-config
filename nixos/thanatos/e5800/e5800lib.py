"""Pure logic for the GL-E5800 poll service. Stdlib only, no I/O -- unit-tested."""
import hashlib


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
