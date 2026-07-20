#!/usr/bin/env bash
# Wi-Fi scan for NetworkPopup.qml. First the nmcli AP list (colon-terse fields),
# then per-BSS signal/age harvested directly from wpa_supplicant over D-Bus
# (emitted as WBSS:<bssid>:<signal>:<age>) since nmcli doesn't expose per-BSS age.
set -u

nmcli -t -f IN-USE,SIGNAL,SECURITY,CHAN,FREQ,RATE,BANDWIDTH,MODE,RSN-FLAGS,BSSID,SSID dev wifi list 2>/dev/null
IFACE=$(nmcli -t -f DEVICE,TYPE dev 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}')
WPAIF=$(busctl --system call fi.w1.wpa_supplicant1 /fi/w1/wpa_supplicant1 fi.w1.wpa_supplicant1 GetInterface s "$IFACE" 2>/dev/null | awk '{print $2}' | tr -d '"')
if [ -n "$WPAIF" ]; then
  BSSES=$(busctl --system get-property fi.w1.wpa_supplicant1 "$WPAIF" fi.w1.wpa_supplicant1.Interface BSSs 2>/dev/null | grep -oE '/fi/w1/wpa_supplicant1/[^" ]*/BSSs/[0-9]+')
  for b in $BSSES; do busctl --system call fi.w1.wpa_supplicant1 "$b" org.freedesktop.DBus.Properties GetAll s fi.w1.wpa_supplicant1.BSS 2>/dev/null; done | awk '
{
  bssid=""; sig=""; age="";
  for(i=1;i<=NF;i++){
    if($i ~ /^"BSSID"$/){ cnt=$(i+2); s=""; for(j=1;j<=cnt;j++){ s=s sprintf("%s%02X",(j>1?":":""),$(i+2+j)); } bssid=s; }
    else if($i ~ /^"Signal"$/){ sig=$(i+2); }
    else if($i ~ /^"Age"$/){ age=$(i+2); }
  }
  if(bssid!="") print "WBSS:" bssid ":" sig ":" age;
}'
fi
