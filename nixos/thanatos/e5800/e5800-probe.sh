#!/usr/bin/env bash
# Survey the GL-E5800's read-only telemetry surface, so we can decide what the
# poller should read and what the popup should show.
#
#   ./e5800-probe.sh [host]              # default 192.168.8.1
#   ./e5800-probe.sh 192.168.8.1 > out   # capture for diffing later
#
# RULE: this script NEVER calls `ubus call modem.CPU.AT ...` and never touches
# /dev/smd9 or /dev/at_mdm0. The AT channel is shared with GL's own gl_modem
# poller; under contention it returns CROSSED RESPONSES -- another command's
# reply. Everything below is either a cellular_manager cache read or a file
# that mudimodem-collectd already publishes, and costs the modem nothing.
#
# Every section is prefixed so the output can be split mechanically, and each
# carries a POPUP note marking what looks worth surfacing.
set -u

HOST="${1:-192.168.8.1}"
USER_="${E5800_USER:-root}"
SSH_KEY="${E5800_SSH_KEY:-}"

ssh_args=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
[ -n "$SSH_KEY" ] && ssh_args+=(-i "$SSH_KEY")

# One connection for the whole survey, same reason the poller uses one: every
# extra connect pays a full handshake against a router whose sshd is slow.
remote() {
    ssh "${ssh_args[@]}" "$USER_@$HOST" "$@"
}

cat <<'BANNER'
=============================================================================
 E5800 telemetry survey -- read-only, no AT
=============================================================================
BANNER

remote 'sh -s' <<'REMOTE'
set -u

sec() { printf '\n===== %s =====\n' "$1"; }
try() { eval "$@" 2>&1 || echo "(failed: $*)"; }

# --- liveness -------------------------------------------------------------
# Exactly the check tools/verify.sh uses. A missing socket is transient
# (procd respawns collectd); treat it as "reconnect", never as fatal.
sec "mudimodem liveness"
[ -S /tmp/mudimodem/collectd.sock ] && echo "socket: UP" || echo "socket: ABSENT"
[ -f /tmp/mudimodem/latest.json ] && echo "latest.json: present" || echo "latest.json: ABSENT"
ls -la /tmp/mudimodem/ 2>/dev/null
echo "-- eMMC speedtest history (survives reboot):"
ls -la /etc/mudimodem/ 2>/dev/null

# --- the published modem sample ------------------------------------------
# POPUP: this replaces cellular.collect get_signals wholesale AND adds fields
# we do not show today -- rssi, dl_bandwidth, tx_channel, serving cell id.
# `carrier` here is the SIM brand (observed: "Mint"), NOT the network.
sec "latest.json (modem sample, 4s cadence)"
try cat /tmp/mudimodem/latest.json

sec "sample history depth"
for f in /tmp/mudimodem/samples.jsonl /tmp/mudimodem/battery.jsonl \
         /tmp/mudimodem/events.jsonl /etc/mudimodem/speedtests.jsonl; do
    [ -f "$f" ] && printf '%-42s %6s lines  %8s bytes\n' \
        "$f" "$(wc -l < "$f")" "$(wc -c < "$f")"
done

# POPUP: band/mode CHANGES over time are handover events. The doc says network
# events are not logged -- you derive them by diffing id/band/mode/slot across
# samples. A "3 handovers in the last hour" line would be genuinely new info.
sec "last 5 modem samples (for handover diffing)"
try tail -n 5 /tmp/mudimodem/samples.jsonl

# POPUP: battery. We show NONE of this today and the router is a battery
# device. cycles/health are wear; temp ran 39-43C in the sample provided,
# which is worth a warning tint. See the limiter trap below.
sec "battery: newest sample"
try tail -n 1 /tmp/mudimodem/battery.jsonl

# POPUP TRAP: `cur == 0 && online == 1` does NOT mean the charge limiter is
# holding. The limiter blocks charge by driving the charger's vreg BELOW the
# cell voltage, which the charger then reports as status=Full + ctype=Trickle
# -- it MANUFACTURES the full-battery signature. Attribute with lim/lim_gauge,
# never with status or cur. Older samples lacking those fields must degrade to
# "idle", never to a confident "full" or "blocked".
sec "battery: limiter attribution fields"
try "tail -n 1 /tmp/mudimodem/battery.jsonl | sed 's/.*\"lim\"/lim/'"
try "which glbattlimit >/dev/null 2>&1 && glbattlimit status"

sec "events (band + cell-lock actions)"
try tail -n 10 /tmp/mudimodem/events.jsonl

sec "speedtest: last result + current run state"
try tail -n 1 /etc/mudimodem/speedtests.jsonl
try cat /tmp/mudimodem/speedtest-status.json

# --- ubus cache reads -----------------------------------------------------
# These are cellular_manager CACHE reads. They do not touch the modem.

# POPUP: the open question. We need the registered NETWORK (T-Mobile) and the
# PLMN to render "Mint (T-Mobile)" and to mark roaming. If mcc/mnc or a
# registration/roaming field lives here, AT+QENG and AT+CEREG both die, and
# the vendored PLMN table plus the whole country-hint mechanism may become
# unnecessary -- the router would already know the answer.
sec "cellular.network info"
try "ubus call cellular.network info '{\"bus\":\"cpu\"}'"
sec "cellular.network status"
try "ubus call cellular.network status '{\"bus\":\"cpu\"}'"

# POPUP: SIM identity. ICCID/IMSI are IDENTIFYING -- do not put them on the
# lock screen, which anyone can read without authenticating. Slot and carrier
# are fine. Also the DSDS caveat: the sample follows `current_sim_slot`, which
# on this box can differ from the slot actually carrying data. Label it
# "selected SIM", not "the connection".
sec "cellular.sim info"
try "ubus call cellular.sim info '{\"bus\":\"cpu\"}'"
sec "cellular.sim status"
try "ubus call cellular.sim status '{\"bus\":\"cpu\"}'"

# POPUP: modem model/firmware/temperature. The popup already shows model and
# firmware from elsewhere; a modem temperature would be new.
sec "cellular.modem status"
try "ubus call cellular.modem status '{\"bus\":\"cpu\"}'"
sec "cellular.modem info"
try "ubus call cellular.modem info '{\"bus\":\"cpu\"}'"

# POPUP: carrier aggregation is the one thing with NO published substitute.
# If the CA view is anywhere outside AT+QCAINFO, it is here.
sec "cellular.modem get_feature_config"
try "ubus call cellular.modem get_feature_config '{\"bus\":\"cpu\"}'"
sec "cellular.modem get_all_config"
try "ubus call cellular.modem get_all_config '{\"bus\":\"cpu\"}'"

# POPUP: could replace our `cat /proc/net/dev` byte-counter read, and may
# already carry per-slot cycle totals -- which would remove the counter
# bookkeeping (usage_step / cycle anchoring) from our side entirely.
sec "cellular.collect get_traffic"
try "ubus call cellular.collect get_traffic '{\"bus\":\"cpu\"}'"

# POPUP: dual-SIM failover state. "Failed over to SIM 2" is exactly the kind
# of thing you want to learn from a glance rather than discover later.
sec "cellular.cm cm_get_status"
try "ubus call cellular.cm cm_get_status '{\"bus\":\"cpu\",\"slot\":1,\"flag\":0}'"

# POPUP: the uplink interface itself -- uptime since last dial, IP, DNS. An
# "up 4h 12m" line distinguishes a stable link from one that keeps redialling.
sec "network.interface.modem_cpu status"
try "ubus call network.interface.modem_cpu status"

# POPUP: charger/OTG state, already used for `plugged`. get_config exposes the
# sleep and auto-shutdown timers, which are worth showing on a battery device.
sec "lpm get_status / get_config"
try "ubus call lpm get_status"
try "ubus call lpm get_config"

# POPUP: the MCU's own warning thresholds -- temperature high/low and capacity.
# Pairing these with the live battery temp turns a number into a verdict.
sec "mcu status / warnings"
try "ubus call mcu status"
try "ubus call mcu get_warning"

# POPUP: router-side load and memory. Useful when the web UI feels slow.
sec "system info / board"
try "ubus call system info"
try "ubus call system board"

# POPUP: the router's own Wi-Fi radios -- channel, width, noise, connected
# clients. We show client COUNT today but not which band they are on.
sec "iwinfo devices"
try "ubus call iwinfo devices"

sec "wifi per-radio info"
for d in $(ubus call iwinfo devices 2>/dev/null | sed -n 's/.*"\(wlan[0-9]*\)".*/\1/p'); do
    echo "-- $d"
    try "ubus call iwinfo info '{\"device\":\"$d\"}'"
done

echo
echo "===== END ====="
REMOTE
