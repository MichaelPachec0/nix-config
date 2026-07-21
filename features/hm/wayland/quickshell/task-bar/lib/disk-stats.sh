#!/usr/bin/env bash
# Filesystem usage + aggregate disk I/O counters for DiskStats.qml.
# Sections are tagged with @D (df rows: target used size pcent), @IO (summed
# read/write sectors across real block devices) and @NOW (ms epoch for the delta).
set -u

echo @D
df -B1024 --output=target,used,size,pcent \
    -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay 2>/dev/null | tail -n +2
echo @IO
awk '$3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]|vd[a-z]|mmcblk[0-9]+)$/ {r+=$6; w+=$10} END {print r, w}' /proc/diskstats
echo @NOW
date +%s%3N
