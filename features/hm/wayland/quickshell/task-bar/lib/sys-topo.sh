#!/usr/bin/env bash
# CPU topology for SysStats.qml (topoPoll, read once). One line per logical CPU:
# "<logical> <core_id> <l3-shared-cpu-list>", sorted numerically. Feeds
# SysFmt.parseTopology so cores can be grouped by CCX.
set -u

for c in /sys/devices/system/cpu/cpu[0-9]*; do
    n=${c##*/cpu}
    printf '%s %s %s\n' "$n" \
        "$(cat "$c/topology/core_id" 2>/dev/null)" \
        "$(cat "$c/cache/index3/shared_cpu_list" 2>/dev/null)"
done | sort -n
