#!/usr/bin/env bash
# Read the ChargerLab POWER-Z KM003C (USB 5fc9:0063) for PowerZStats.qml.
# Emits a `state:` line always, plus raw sysfs readings when active. ALWAYS
# exits 0 -- a nonzero exit makes CommandPoll keep its last-good value and would
# mask a state change (see lib/CommandPoll.qml).
#
#   state: active   powerz hwmon bound on interface 1.0 -> vbus/ibus/cc1/cc2 follow
#   state: busy     device enumerated but hwmon gone (another app claimed 1.0)
#   state: absent   device not present on USB
#
# Raw integer sysfs units (mV / mA); PowerZStats converts to V/A. Read-only:
# this never opens a USB interface and cannot lock the meter.
set -u

# 1. Find the powerz hwmon node by NAME (the hwmonN index is not stable).
hw=""
for n in /sys/class/hwmon/*/name; do
    [ -r "$n" ] || continue
    if [ "$(cat "$n" 2>/dev/null)" = "powerz" ]; then
        hw="${n%/name}"
        break
    fi
done

if [ -n "$hw" ]; then
    printf 'state: active\n'
    [ -r "$hw/in0_input" ]   && printf 'vbus: %s\n' "$(cat "$hw/in0_input" 2>/dev/null)"
    [ -r "$hw/curr1_input" ] && printf 'ibus: %s\n' "$(cat "$hw/curr1_input" 2>/dev/null)"
    [ -r "$hw/in1_input" ]   && printf 'cc1: %s\n'  "$(cat "$hw/in1_input" 2>/dev/null)"
    [ -r "$hw/in2_input" ]   && printf 'cc2: %s\n'  "$(cat "$hw/in2_input" 2>/dev/null)"
    exit 0
fi

# 2. No hwmon: is the KM003C still enumerated on USB? -> busy, else absent.
for d in /sys/bus/usb/devices/*/; do
    [ -r "$d/idVendor" ] || continue
    if [ "$(cat "$d/idVendor" 2>/dev/null)" = "5fc9" ] \
       && [ "$(cat "$d/idProduct" 2>/dev/null)" = "0063" ]; then
        printf 'state: busy\n'
        exit 0
    fi
done

printf 'state: absent\n'
exit 0
