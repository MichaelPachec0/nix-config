#!/usr/bin/env bash
# Primary network status probe for NetworkService.qml (statusPoll). Emits K:V
# lines the QML parses: WIFI/HASWIFI/CONNECTIVITY radio+reachability, IFACE/IP/GW
# primary route, PTYPE/CNAME active connection, WUUID/STATE/SSID/SIGNAL/BSSID for
# the active Wi-Fi, and one CONN:<uuid>|<name>|<type>|<up|down>|<ip>|<gw> per
# non-Wi-Fi saved profile.
# Health probe: if NetworkManager is momentarily unreachable this tick, exit
# nonzero so CommandPoll keeps the last-good reading instead of blanking the bar
# to Off/Disconnected for a cycle. (Doubles as the WIFI radio read.)
#
# FORK BUDGET. This is the shell's only ungated poller -- it runs every 4s for
# the whole session (the lock screen consumes the same NetworkService, so it
# cannot be gated on bar visibility alone). It used to fork 22 children per tick
# and take ~196ms; each nmcli round-trip costs ~17ms and they are serial, so the
# fork count WAS the runtime. It now forks 7 and takes ~106ms, by issuing a
# fixed set of BULK queries and doing all the matching in-process:
#
#   nmcli -t -f WIFI,CONNECTIVITY general status         radio + reachability
#   ip    -o route get 1.1.1.1                           primary dev/src/via
#   nmcli -t -f GENERAL.DEVICE,... device show           per-device type/ip/gw
#   nmcli -t -f UUID,NAME,... connection show --active   what is up, and where
#   nmcli -t -f UUID,NAME,TYPE connection show           every saved profile
#   (+ the ssid and `dev wifi list` reads, only while associated)
#
# The per-profile loop was the worst of it: 1-3 nmcli PER SAVED PROFILE, for
# values that are all already present in the dumps above -- NAME comes straight
# out of `connection show`, and IP4.ADDRESS/IP4.GATEWAY out of `device show`
# matched on GENERAL.CON-UUID. Adding a profile is now free.
#
# Do NOT reintroduce a per-item nmcli call here. If a new field is needed, add
# it to one of the existing -f lists first: nmcli returns the whole table for
# the same ~17ms it charges for a single value.
set -u

# Split an `nmcli -t` line into F[], honouring terse escaping: nmcli backslash-
# escapes ':' and '\' inside a field, so a profile named "Foo:Bar" arrives as
# "Foo\:Bar" and a naive split on ':' shifts every later field. (The `awk -F:`
# this replaced had exactly that bug -- a colon in a connection name misread the
# DEVICE column and dropped CNAME.) Pure bash, no fork.
nm_split() {
    local line=$1 cur="" i c
    F=()
    for ((i = 0; i < ${#line}; i++)); do
        c=${line:i:1}
        if [ "$c" = "\\" ]; then
            i=$((i + 1))
            cur+=${line:i:1}
        elif [ "$c" = ':' ]; then
            F+=("$cur")
            cur=""
        else
            cur+=$c
        fi
    done
    F+=("$cur")
}

# --- radio + reachability ---------------------------------------------------
# One `general status` covers both. Also the health probe: a nonzero exit means
# NetworkManager did not answer, and CommandPoll keeps its last-good value
# rather than flashing the bar to Off for a tick.
GEN=$(nmcli -t -f WIFI,CONNECTIVITY general status 2>/dev/null) || exit 1
nm_split "${GEN%%$'\n'*}"
WIFI=${F[0]-}
echo "WIFI:$WIFI"
case "$WIFI" in enabled | disabled) echo "HASWIFI:1" ;; *) echo "HASWIFI:0" ;; esac
echo "CONNECTIVITY:${F[1]-}"

# --- primary route ----------------------------------------------------------
# dev/src/via out of one `ip route get`, parsed through the positional
# parameters instead of awk. `set -f` first: the route line is deliberately
# unquoted here, and a glob character in it would otherwise expand against cwd.
PDEV=""
PIP=""
PGW=""
ROUTE=$(ip -o route get 1.1.1.1 2>/dev/null)
set -f
# shellcheck disable=SC2086
set -- $ROUTE
set +f
while [ $# -gt 0 ]; do
    case $1 in
    dev) PDEV=${2-} ;;
    src) PIP=${2-} ;;
    via) PGW=${2-} ;;
    esac
    shift
done
echo "IFACE:$PDEV"
echo "IP:$PIP"
echo "GW:$PGW"

# --- one device dump --------------------------------------------------------
# GENERAL.DEVICE opens each block, a blank line closes it. None of the requested
# fields can contain a ':' (interface names cannot, and IP4.* is v4-only), so a
# split on the first ':' is enough and nm_split's per-character loop is not
# worth paying for across the ~50 lines this produces.
declare -A DEV_TYPE=() UUID_IP=() UUID_GW=()
_dev=""
_type=""
_uuid=""
_ip=""
_gw=""
_flush_dev() {
    [ -n "$_dev" ] || return 0
    DEV_TYPE[$_dev]=$_type
    if [ -n "$_uuid" ]; then
        UUID_IP[$_uuid]=$_ip
        UUID_GW[$_uuid]=$_gw
    fi
}
while IFS= read -r line; do
    if [ -z "$line" ]; then
        _flush_dev
        _dev=""
        _type=""
        _uuid=""
        _ip=""
        _gw=""
        continue
    fi
    k=${line%%:*}
    v=${line#*:}
    case "$k" in
    GENERAL.DEVICE) _dev=$v ;;
    GENERAL.TYPE) _type=$v ;;
    GENERAL.CON-UUID) _uuid=$v ;;
    # First address only, /prefix stripped -- exactly what the old
    # `nmcli -g IP4.ADDRESS ... | head -n1 | cut -d/ -f1` produced.
    'IP4.ADDRESS[1]') _ip=${v%%/*} ;;
    IP4.GATEWAY) _gw=$v ;;
    esac
done < <(nmcli -t -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.CON-UUID,IP4.ADDRESS,IP4.GATEWAY device show 2>/dev/null)
_flush_dev

# --- one active-connection dump ---------------------------------------------
# Carries the primary connection's name (matched on DEVICE), the active Wi-Fi
# profile's uuid/state, and the set of uuids that are up.
declare -A ACTIVE=()
CNAME=""
WUUID=""
WSTATE=""
while IFS= read -r line; do
    [ -n "$line" ] || continue
    nm_split "$line"
    u=${F[0]-}
    n=${F[1]-}
    t=${F[2]-}
    d=${F[3]-}
    s=${F[4]-}
    [ -n "$u" ] && ACTIVE[$u]=1
    # First match wins for both, as before.
    if [ -n "$PDEV" ] && [ "$d" = "$PDEV" ] && [ -z "$CNAME" ]; then
        CNAME=$n
    fi
    if [ "$t" = "802-11-wireless" ] && [ -z "$WUUID" ]; then
        WUUID=$u
        WSTATE=$s
    fi
done < <(nmcli -t -f UUID,NAME,TYPE,DEVICE,STATE connection show --active 2>/dev/null)

PTYPE=none
if [ -n "$PDEV" ]; then
    T=${DEV_TYPE[$PDEV]-}
    case "$T" in
    wifi) PTYPE=wifi ;;
    ethernet) PTYPE=ethernet ;;
    # Passthrough, including the empty string when the device is not in the dump
    # at all -- the old `nmcli -g GENERAL.TYPE device show <dev>` printed nothing
    # in that case and PTYPE went out empty. Preserved.
    *) PTYPE="$T" ;;
    esac
    echo "CNAME:$CNAME"
fi
echo "PTYPE:$PTYPE"
echo "WUUID:$WUUID"
if [ -n "$WUUID" ]; then
    [ "$WSTATE" = "activated" ] && echo "STATE:activated" || echo "STATE:activating"
    SSID=$(nmcli -g 802-11-wireless.ssid connection show uuid "$WUUID" 2>/dev/null)
    echo "SSID:${SSID%%$'\n'*}"
    # One `nmcli dev wifi list`: the active (IN-USE=*) row carries both SIGNAL
    # and BSSID. -g escapes ':' in the BSSID as '\:', so drop the "*:" prefix,
    # take SIGNAL up to the next ':', then de-escape the rest as the BSSID.
    #
    # NOTE: this call is the one that touches the radio. `nmcli dev wifi list`
    # without --rescan guarantees the AP list is no older than 30s and triggers
    # a scan if it is not, so at a 4s cadence NetworkManager is made to scan
    # every ~30s for as long as we stay associated. `--rescan no` would stop
    # that at the cost of a SIGNAL reading that goes stale -- a behaviour
    # change, so deliberately NOT made here.
    SIGNAL=""
    BSSID=""
    while IFS= read -r line; do
        case "$line" in
        '*:'*) ;;
        *) continue ;;
        esac
        _w=${line#*:}
        SIGNAL=${_w%%:*}
        BSSID=${_w#*:}
        BSSID=${BSSID//\\/}
        break
    done < <(nmcli -g IN-USE,SIGNAL,BSSID dev wifi list 2>/dev/null)
    echo "SIGNAL:$SIGNAL"
    echo "BSSID:$BSSID"
elif [ "$PTYPE" = "ethernet" ]; then
    echo "STATE:activated"
else
    echo "STATE:disconnected"
fi

# --- every saved profile ----------------------------------------------------
# All non-Wi-Fi profiles become chips/rows (ethernet/vpn/wireguard/...). Wi-Fi
# has its own scan list; loopback is noise. NAME arrives with the dump, and
# ip/gateway come from the device dump keyed by the active uuid -- no forks.
while IFS= read -r line; do
    [ -n "$line" ] || continue
    nm_split "$line"
    u=${F[0]-}
    n=${F[1]-}
    t=${F[2]-}
    case "$t" in 802-11-wireless | loopback) continue ;; esac
    st=down
    cip=""
    cgw=""
    if [ -n "${ACTIVE[$u]-}" ]; then
        st=up
        cip=${UUID_IP[$u]-}
        cgw=${UUID_GW[$u]-}
    fi
    echo "CONN:$u|$n|$t|$st|$cip|$cgw"
done < <(nmcli -t -f UUID,NAME,TYPE connection show 2>/dev/null)
