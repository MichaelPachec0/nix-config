#!/usr/bin/env bash
# Primary-battery detail via upower, for BatteryPopup.qml and InhibitPopup.qml.
# No arg: the full `upower -i` block. Arg "tte": only the "time to empty" value
# (used for the sleep-inhibit countdown).
set -u

info=$(upower -i "$(upower -e | grep -Ei 'battery_BAT' | head -1)" 2>/dev/null)
if [ "${1:-}" = tte ]; then
    printf '%s\n' "$info" | sed -n 's/.*time to empty:[[:space:]]*//p'
else
    printf '%s\n' "$info"
fi
