#!/usr/bin/env bash
# Snapshot every counter the zswap soak judges, one key=value line, so two
# snapshots taken around a build or a hibernate can be diffed by eye or awk.
#
# Run as root (debugfs is root-only). Appends to $1, default ./zswap-soak.log.
# Under sudo the log is created by root; chown it back if your editor minds.
# Pair with the intent:
#   vmstat zswpout/zswpin/zswpwb   all move; zswpwb > 0 during a build
#   user.slice zswpwb              small next to nix-daemon's
#   nix-daemon zswap.current       <= MemoryZSwapMax (2G)
#   debug reject_compress_poor     ~0 (incompressible pages are stored raw)
#   debug pool_limit_hit           low; climbing means raise max_pool_percent
#   user.slice oom_kill            0
#   thp_zswpout                    zswap-era THP counter; growth argues mTHP
#     (thp_swpout now only counts THPs that bypassed the pool, to disk)
#   meminfo Zswapped/SwapFree      before every hibernate
set -euo pipefail

out="${1:-./zswap-soak.log}"
cg=/sys/fs/cgroup
us="$cg/user.slice"
nd="$cg/system.slice/nix-daemon.service"
dbg=/sys/kernel/debug/zswap

kv() { printf '%s=%s ' "$1" "$2"; }
vm_stat() { awk -v k="$1" '$1 == k { print $2; found = 1 } END { if (!found) print "na" }' /proc/vmstat; }
meminfo() { awk -v k="$1:" '$1 == k { print $2; found = 1 } END { if (!found) print "na" }' /proc/meminfo; }
cg_stat() { awk -v k="$2" '$1 == k { print $2; found = 1 } END { if (!found) print "na" }' "$1/memory.stat" 2>/dev/null || echo na; }
events() { awk -v k="$2" '$1 == k { print $2; found = 1 } END { if (!found) print "na" }' "$1/memory.events" 2>/dev/null || echo na; }
rd() { cat "$1" 2>/dev/null || echo na; }

{
  kv ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  kv zswap_enabled "$(rd /sys/module/zswap/parameters/enabled)"
  kv compressor "$(rd /sys/module/zswap/parameters/compressor)"
  kv max_pool_percent "$(rd /sys/module/zswap/parameters/max_pool_percent)"
  kv shrinker_enabled "$(rd /sys/module/zswap/parameters/shrinker_enabled)"
  kv accept_threshold_percent "$(rd /sys/module/zswap/parameters/accept_threshold_percent)"
  kv zram_active "$(swapon --noheadings --show=NAME | grep -c zram || true)"
  kv zswpout "$(vm_stat zswpout)"
  kv zswpin "$(vm_stat zswpin)"
  kv zswpwb "$(vm_stat zswpwb)"
  kv pswpout "$(vm_stat pswpout)"
  kv pswpin "$(vm_stat pswpin)"
  kv thp_swpout "$(vm_stat thp_swpout)"
  kv thp_zswpout "$(rd /sys/kernel/mm/transparent_hugepage/hugepages-2048kB/stats/zswpout)"
  kv pgsteal_direct "$(vm_stat pgsteal_direct)"
  kv pgsteal_kswapd "$(vm_stat pgsteal_kswapd)"
  kv meminfo_zswap_kb "$(meminfo Zswap)"
  kv meminfo_zswapped_kb "$(meminfo Zswapped)"
  kv meminfo_swapfree_kb "$(meminfo SwapFree)"
  kv us_zswpwb "$(cg_stat "$us" zswpwb)"
  kv us_pswpout "$(cg_stat "$us" pswpout)"
  kv us_zswpout "$(cg_stat "$us" zswpout)"
  kv us_zswapped "$(cg_stat "$us" zswapped)"
  kv us_swapcached "$(cg_stat "$us" swapcached)"
  kv us_zswap_incomp "$(cg_stat "$us" zswap_incomp)"
  kv us_swap_current "$(rd "$us/memory.swap.current")"
  kv us_zswap_current "$(rd "$us/memory.zswap.current")"
  kv us_low_events "$(events "$us" low)"
  kv us_oom_kill "$(events "$us" oom_kill)"
  kv us_psi_mem_some "$(awk '/^some/ { sub("total=", "", $5); print $5 }' "$us/memory.pressure" 2>/dev/null || echo na)"
  kv nd_zswpwb "$(cg_stat "$nd" zswpwb)"
  kv nd_pswpout "$(cg_stat "$nd" pswpout)"
  kv nd_zswpout "$(cg_stat "$nd" zswpout)"
  kv nd_zswap_incomp "$(cg_stat "$nd" zswap_incomp)"
  kv nd_zswap_current "$(rd "$nd/memory.zswap.current")"
  kv nd_zswap_max "$(rd "$nd/memory.zswap.max")"
  kv nd_high_events "$(events "$nd" high)"
  kv dbg_pool_total_size "$(rd "$dbg/pool_total_size")"
  kv dbg_stored_pages "$(rd "$dbg/stored_pages")"
  kv dbg_written_back_pages "$(rd "$dbg/written_back_pages")"
  kv dbg_pool_limit_hit "$(rd "$dbg/pool_limit_hit")"
  kv dbg_reject_reclaim_fail "$(rd "$dbg/reject_reclaim_fail")"
  kv dbg_reject_compress_poor "$(rd "$dbg/reject_compress_poor")"
  kv dbg_reject_alloc_fail "$(rd "$dbg/reject_alloc_fail")"
  echo
} | tee -a "$out"
