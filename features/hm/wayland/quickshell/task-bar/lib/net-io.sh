#!/usr/bin/env bash
# Per-interface rx/tx byte counters for NetStats.qml. One line per carrier-up,
# non-loopback interface ("<iface> <rx> <tx>"), plus "@NOW <ms epoch>" for the
# rate delta.
set -u

for i in /sys/class/net/*; do
    n=${i##*/}
    [ "$n" = lo ] && continue
    [ "$(cat "$i/carrier" 2>/dev/null)" = 1 ] || continue
    echo "$n $(cat "$i/statistics/rx_bytes" 2>/dev/null) $(cat "$i/statistics/tx_bytes" 2>/dev/null)"
done
echo "@NOW $(date +%s%3N)"
