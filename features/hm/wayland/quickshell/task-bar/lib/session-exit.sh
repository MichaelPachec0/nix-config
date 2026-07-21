#!/usr/bin/env bash
# Log out of the graphical session. UWSM-managed: graceful `uwsm stop`, else
# exit Hyprland directly. Used by the hub power menu (Header.qml).
set -u

if command -v uwsm >/dev/null 2>&1; then
    uwsm stop || hyprctl dispatch exit
else
    hyprctl dispatch exit
fi
