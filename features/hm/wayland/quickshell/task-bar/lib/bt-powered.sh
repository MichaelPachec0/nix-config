#!/usr/bin/env bash
# Bluetooth controller power state ("on"/"off") for the hub ButtonsSlidersCard
# toggle.
set -u

bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off
