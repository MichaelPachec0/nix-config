#!/usr/bin/env bash
# Saved Wi-Fi connection names (~= SSIDs) for NetworkPopup.qml, so secured-but-
# saved networks can be shown as known. One profile name per line.
set -u

nmcli -t -f NAME,TYPE connection show 2>/dev/null | awk -F: '$2=="802-11-wireless"{print $1}'
