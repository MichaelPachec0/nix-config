#!/usr/bin/env bash
# Active Wi-Fi AP detail for NetworkInfoPopup.qml (read-only hover panel). Reads
# the associated AP via NetworkManager D-Bus (BSSID/SIGNAL/FREQ/RATE/RSN/WPA),
# the primary route IP/GW, then richer link stats from wpa_supplicant's
# SignalPoll (RSSI/NOISE/LINKSPEED/WIDTH) and derives the PHY (Wi-Fi 4-7).
# Exits 0 early with no output when there is no associated AP.
set -u

IFACE=$(nmcli -t -f DEVICE,TYPE dev 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}')
[ -z "$IFACE" ] && exit 0
NM=org.freedesktop.NetworkManager
gp(){ busctl --system get-property "$NM" "$1" "$2" "$3" 2>/dev/null; }
DEV=$(busctl --system call "$NM" /org/freedesktop/NetworkManager "$NM" GetDeviceByIpIface s "$IFACE" 2>/dev/null | awk '{print $NF}' | tr -d '"')
[ -z "$DEV" ] && exit 0
AP=$(gp "$DEV" "$NM.Device.Wireless" ActiveAccessPoint | awk '{print $NF}' | tr -d '"')
{ [ -z "$AP" ] || [ "$AP" = "/" ]; } && exit 0
echo "BSSID:$(gp "$AP" "$NM.AccessPoint" HwAddress | sed -E 's/^s //; s/"//g')"
echo "SIGNAL:$(gp "$AP" "$NM.AccessPoint" Strength | awk '{print $NF}')"
echo "FREQ:$(gp "$AP" "$NM.AccessPoint" Frequency | awk '{print $NF}')"
echo "RATE:$(gp "$DEV" "$NM.Device.Wireless" Bitrate | awk '{print $NF}')"
echo "RSN:$(gp "$AP" "$NM.AccessPoint" RsnFlags | awk '{print $NF}')"
echo "WPA:$(gp "$AP" "$NM.AccessPoint" WpaFlags | awk '{print $NF}')"
echo "IP:$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')"
echo "GW:$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="via"){print $(i+1);exit}}')"
WPAIF=$(busctl --system call fi.w1.wpa_supplicant1 /fi/w1/wpa_supplicant1 fi.w1.wpa_supplicant1 GetInterface s "$IFACE" 2>/dev/null | awk '{print $NF}' | tr -d '"')
if [ -n "$WPAIF" ]; then
  SP=$(busctl --system call fi.w1.wpa_supplicant1 "$WPAIF" fi.w1.wpa_supplicant1.Interface SignalPoll 2>/dev/null)
  echo "RSSI:$(printf '%s' "$SP" | grep -oE '"rssi" [a-z] -?[0-9]+' | awk '{print $NF}')"
  echo "NOISE:$(printf '%s' "$SP" | grep -oE '"noise" [a-z] -?[0-9]+' | awk '{print $NF}')"
  echo "LINKSPEED:$(printf '%s' "$SP" | grep -oE '"linkspeed" [a-z] -?[0-9]+' | awk '{print $NF}')"
  echo "WIDTH:$(printf '%s' "$SP" | grep -oE '"width" s "[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/')"
  if echo "$SP" | grep -q 'eht-mcs'; then echo "PHY:802.11be (Wi-Fi 7)"
  elif echo "$SP" | grep -q 'he-mcs'; then echo "PHY:802.11ax (Wi-Fi 6)"
  elif echo "$SP" | grep -q 'vht-mcs'; then echo "PHY:802.11ac (Wi-Fi 5)"
  elif echo "$SP" | grep -q 'ht-mcs'; then echo "PHY:802.11n (Wi-Fi 4)"
  else echo "PHY:802.11a/g"; fi
fi
