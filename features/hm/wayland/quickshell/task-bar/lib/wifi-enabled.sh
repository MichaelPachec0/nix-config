#!/usr/bin/env bash
# Wi-Fi radio state ("enabled"/"disabled") for the hub ButtonsSlidersCard toggle.
set -u

nmcli -t -f WIFI g 2>/dev/null | head -n1 || true
