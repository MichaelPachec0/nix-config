#!/usr/bin/env bash
# Per-core CPU jiffies + current frequency for SysStats.qml (perCorePoll).
# First block: /proc/stat per-cpu lines. After the @F marker: "<logical> <khz>"
# per core, sorted numerically so the QML indexes line up.
set -u

grep '^cpu[0-9]' /proc/stat
echo @F
for c in /sys/devices/system/cpu/cpu[0-9]*; do
    n=${c##*/cpu}
    printf '%s %s\n' "$n" "$(cat "$c/cpufreq/scaling_cur_freq" 2>/dev/null)"
done | sort -n
