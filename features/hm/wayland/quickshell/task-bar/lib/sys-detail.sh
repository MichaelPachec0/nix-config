#!/usr/bin/env bash
# Point-in-time system detail for SysStats.qml (detailPoll). Tagged sections:
# @L loadavg, @M meminfo, @P PSI (cpu then memory), @U uptime, @T zenpower die
# temp, @TM top-6 by RSS, @TC top-6 by CPU. No deltas needed here.
set -u

echo @L
cat /proc/loadavg
echo @M
cat /proc/meminfo
echo @P
head -1 /proc/pressure/cpu
head -1 /proc/pressure/memory
echo @U
cat /proc/uptime
echo @T
for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = zenpower ] && cat "$h/temp1_input" 2>/dev/null && break
done
echo @TM
ps -eo pid,rss,pmem,comm --sort=-rss | head -6
echo @TC
ps -eo pid,pcpu,comm --sort=-pcpu | head -6
