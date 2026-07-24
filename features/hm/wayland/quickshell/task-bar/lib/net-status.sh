#!/usr/bin/env bash
# Primary network status probe for NetworkService.qml (statusPoll). Emits K:V
# lines the QML parses: WIFI/HASWIFI/CONNECTIVITY radio+reachability, IFACE/IP/GW
# primary route, PTYPE/CNAME active connection, WUUID/STATE/SSID/SIGNAL/BSSID for
# the active Wi-Fi, and one CONN:<uuid>|<name>|<type>|<up|down>|<ip>|<gw> per
# non-Wi-Fi saved profile.
# Health probe: if NetworkManager is momentarily unreachable this tick, exit
# nonzero so CommandPoll keeps the last-good reading instead of blanking the bar
# to Off/Disconnected for a cycle. (Doubles as the WIFI radio read.)
set -u

WIFI=$(nmcli -g WIFI radio 2>/dev/null) || exit 1
echo "WIFI:$WIFI"
case "$WIFI" in enabled | disabled) echo "HASWIFI:1" ;; *) echo "HASWIFI:0" ;; esac
echo "CONNECTIVITY:$(nmcli -g CONNECTIVITY general status 2>/dev/null)"

# One `ip route get` instead of three: pull dev/src/via together, |-delimited so
# an empty field (e.g. a direct route with no via) is preserved positionally.
ROUTE=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{d=s=g="";for(i=1;i<=NF;i++){if($i=="dev")d=$(i+1);else if($i=="src")s=$(i+1);else if($i=="via")g=$(i+1)}printf "%s|%s|%s",d,s,g}')
PDEV=${ROUTE%%|*}; _r=${ROUTE#*|}; PIP=${_r%%|*}; PGW=${_r#*|}
echo "IFACE:$PDEV"
echo "IP:$PIP"
echo "GW:$PGW"

PTYPE=none
if [ -n "$PDEV" ]; then
  T=$(nmcli -g GENERAL.TYPE device show "$PDEV" 2>/dev/null)
  case "$T" in wifi) PTYPE=wifi;; ethernet) PTYPE=ethernet;; *) PTYPE="$T";; esac
  echo "CNAME:$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: -v d="$PDEV" '$2==d{print $1; exit}')"
fi
echo "PTYPE:$PTYPE"
WROW=$(nmcli -t -f UUID,TYPE,STATE connection show --active 2>/dev/null | awk -F: '$2=="802-11-wireless"{print; exit}')
WUUID=$(printf '%s' "$WROW" | cut -d: -f1)
echo "WUUID:$WUUID"
if [ -n "$WUUID" ]; then
  WSTATE=$(printf '%s' "$WROW" | cut -d: -f3)
  [ "$WSTATE" = "activated" ] && echo "STATE:activated" || echo "STATE:activating"
  echo "SSID:$(nmcli -g 802-11-wireless.ssid connection show uuid "$WUUID" 2>/dev/null | head -n1)"
  # One `nmcli dev wifi list` instead of two: the active (IN-USE=*) row carries
  # both SIGNAL and BSSID. -g escapes ':' in the BSSID as '\:', so drop the "*:"
  # prefix, take SIGNAL up to the next ':', then de-escape the rest as the BSSID.
  SIGNAL=""; BSSID=""
  WIFILINE=$(nmcli -g IN-USE,SIGNAL,BSSID dev wifi list 2>/dev/null | grep -m1 '^\*:')
  if [ -n "$WIFILINE" ]; then
    _w=${WIFILINE#*:}
    SIGNAL=${_w%%:*}
    BSSID=$(printf '%s' "${_w#*:}" | tr -d '\\')
  fi
  echo "SIGNAL:$SIGNAL"
  echo "BSSID:$BSSID"
elif [ "$PTYPE" = "ethernet" ]; then
  echo "STATE:activated"
else
  echo "STATE:disconnected"
fi
ACT=$(nmcli -t -f UUID connection show --active 2>/dev/null)
nmcli -t -f UUID,TYPE connection show 2>/dev/null | while IFS=: read -r u t; do
  # All non-Wi-Fi profiles become chips/rows (ethernet/vpn/wireguard/...).
  # Wi-Fi has its own scan list; loopback is noise.
  case "$t" in 802-11-wireless | loopback) continue ;; esac
  n=$(nmcli -g connection.id connection show uuid "$u" 2>/dev/null)
  st=down; cip=""; cgw=""
  if printf '%s\n' "$ACT" | grep -qx "$u"; then
    st=up
    cip=$(nmcli -g IP4.ADDRESS connection show uuid "$u" 2>/dev/null | head -n1 | cut -d/ -f1)
    cgw=$(nmcli -g IP4.GATEWAY connection show uuid "$u" 2>/dev/null | head -n1)
  fi
  echo "CONN:$u|$n|$t|$st|$cip|$cgw"
done
