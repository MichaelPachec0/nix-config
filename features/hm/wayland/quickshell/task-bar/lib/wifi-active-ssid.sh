#!/usr/bin/env bash
# SSID of the active Wi-Fi connection for the hub ButtonsSlidersCard label.
set -u

nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}' || true
