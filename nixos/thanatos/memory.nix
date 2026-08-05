{
  lib,
  pkgs,
  ...
}: let
  # Ryzen 7 PRO 4750U / 21.2 GiB usable (MemTotal 22254768 kB). Every absolute
  # value below is derived from that figure -- recheck them if the RAM changes.
  memTotalKb = 22254768;

  zramDev = "/sys/block/zram0";

  # Desktop working set we refuse to reclaim before anything else. Best-effort
  # (memory.low, not memory.min), so reclaim can still take it as a last resort.
  guiReserve = "10G";

  # memory.low only takes effect if every ancestor also grants it: the effective
  # protection is min(own, parent's undistributed share). Breaking the chain at
  # any level silently reduces protection to zero, so all four are set together.
  #   user.slice -> user-.slice -> user@.service -> session.slice
  protectSlice = {
    overrideStrategy = "asDropin";
    sliceConfig = {
      MemoryAccounting = true;
      MemoryLow = guiReserve;
      # oomd may only pick these once no unprotected candidate is left.
      ManagedOOMPreference = "avoid";
    };
  };
in {
  # ---- sysctl (thanatos-only; RAM-size dependent) -------------------------
  # The zram policy quad (swappiness / page-cluster / watermark_*) stays in the
  # shared nyx/configuration.nix -- it is a property of running zram at all, not
  # of this machine's RAM.
  boot.kernel.sysctl = {
    # ~1% of MemTotal. Headroom for zram's own allocations during swap-out;
    # starving this deadlocks reclaim (zram needs free pages to compress into).
    "vm.min_free_kbytes" = memTotalKb / 100;

    # Bound writeback by bytes, not by percent-of-RAM. The 20%/10% defaults let
    # ~4.2G of dirty pages queue up, and draining that stalls swap-in behind it
    # on the same NVMe. Setting *_bytes zeroes the matching *_ratio; they are
    # mutually exclusive, so do not reintroduce vm.dirty_ratio here.
    "vm.dirty_bytes" = 256 * 1024 * 1024;
    "vm.dirty_background_bytes" = 64 * 1024 * 1024;

    # THP is madvise-only, so proactive compaction only spends latency building
    # huge pages nothing asked for. compact_stall was ~10k before this.
    "vm.compaction_proactiveness" = 0;
  };

  # ---- zram ---------------------------------------------------------------
  # Measured ratio is ~4.2x (3.77G orig -> 922M compressed), so 100% of RAM as
  # disksize holds roughly all of it in ~5G of actual RAM. disksize is virtual;
  # real consumption is the compressed size. At 50% zram filled and spilled ~8G
  # onto the NVMe swap, which is the slow tier this whole file exists to avoid.
  zramSwap.memoryPercent = lib.mkForce 100;

  # Secondary (higher-ratio) compression tier for cold pages. CONFIG_ZRAM_MULTI_COMP=y
  # and CONFIG_ZRAM_WRITEBACK=y on this kernel, but CONFIG_ZRAM_TRACK_ENTRY_ACTIME
  # is NOT set -- so age-based marking (`echo 3600 > idle`) does not work and only
  # `echo all > idle` is available. The timer works around that by recompressing
  # last round's marks *before* re-marking: a page touched during the interval has
  # its idle flag cleared by the access, so only genuinely cold pages get hit.
  systemd.services.zram-recompress = {
    description = "Recompress cold zram pages with the secondary algorithm";
    after = ["systemd-zram-setup@zram0.service"];
    requires = ["systemd-zram-setup@zram0.service"];
    serviceConfig = {
      Type = "oneshot";
      # Cold-path maintenance; must never compete with the desktop.
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    path = [pkgs.coreutils];
    script = ''
      set -u
      dev=${zramDev}
      [ -e "$dev/recomp_algorithm" ] || exit 0

      # Idempotent: re-declaring the same secondary algorithm is a no-op.
      echo "algo=deflate priority=1" > "$dev/recomp_algorithm" || exit 0

      # Pages stored uncompressed because the primary could not shrink them.
      # deflate sometimes can; costs nothing when it cannot.
      echo "type=huge" > "$dev/recompress" || true

      # Acts on the marks set at the END of the previous run (see above).
      echo "type=idle" > "$dev/recompress" || true

      # Arm the next round.
      echo all > "$dev/idle" || true
    '';
  };

  systemd.timers.zram-recompress = {
    description = "Periodic zram cold-page recompression";
    wantedBy = ["timers.target"];
    timerConfig = {
      # First run only arms the idle marks; recompression starts one cycle later.
      OnBootSec = "15min";
      OnUnitActiveSec = "30min";
      # The interval doubles as the "how long is cold" threshold, so do not let
      # the persistent catch-up collapse it to zero.
      Persistent = false;
    };
  };

  # ---- MGLRU --------------------------------------------------------------
  # MGLRU is on (lru_gen/enabled = 0x0007) but min_ttl_ms defaults to 0, i.e.
  # unused. A nonzero TTL tells reclaim to OOM rather than evict a working set
  # younger than this -- it protects exactly the pages whose eviction you feel,
  # which no swappiness value can express. Conservative on purpose: raising it
  # trades "stall" for "kill", and only makes sense with oomd armed below.
  systemd.tmpfiles.rules = [
    "w- /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000"
  ];

  # ---- systemd-oomd -------------------------------------------------------
  # oomd was already running but `oomctl` showed both monitor lists empty, so it
  # was inert. Root slice gives a system-wide safety net; user slices are left
  # OFF deliberately so a Firefox tab is never the default victim.
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableSystemSlice = false;
    enableUserSlices = false;
  };

  # ---- Tiered swap pressure ----------------------------------------------
  # cgroup v2 has no per-cgroup swappiness (memory.swappiness is v1 only, and is
  # absent here), and swap priority only picks the *device*. So "who gets evicted"
  # is expressed as: MemoryHigh on the greedy side, MemoryLow on the protected
  # side.

  # Greedy side. MemoryHigh is not a hard cap -- crossing it forces reclaim on
  # this cgroup, which pushes builder anon pages to zram and drops their page
  # cache. That is the eager eviction, and it is the only mechanism that does it.
  # Builds needing more than this get slower, not killed; raise it if that bites.
  #
  # Deliberately NO CPUWeight here: cgroup weights are relative among *siblings*,
  # so lowering nix-daemon's weight only ranks it against other system.slice
  # services. The desktop lives in user.slice, a different subtree, so it would
  # not have been affected at all. SCHED_IDLE below is the cross-tree knob.
  systemd.services.nix-daemon.serviceConfig = {
    MemoryAccounting = true;
    MemoryHigh = "8G";
    # Explicit, not inherited: claim no reclaim protection at all.
    MemoryLow = "0";
    # When system swap crosses oomd's 90% limit, this is the preferred casualty.
    ManagedOOMSwap = "kill";
  };

  # Build priority. NixOS defaults these to "other"/"best-effort" -- i.e. builders
  # ran at exactly the same priority as Firefox. Scheduling policy and I/O class
  # are both inherited across fork/exec, so setting them on the daemon covers
  # every builder it spawns.
  #
  # SCHED_IDLE gives a task weight of 3 against 1024 for nice 0, so builds get
  # CPU only when nothing interactive wants it. Costs build throughput on an idle
  # machine roughly not at all, since "nothing else wants the CPU" is the common
  # case during a rebuild.
  nix.daemonCPUSchedPolicy = "idle";
  # Class 3 (idle) ignores the numeric priority, so daemonIOSchedPriority is
  # left alone. See the mq-deadline rule below -- this is inert without it.
  nix.daemonIOSchedClass = "idle";

  # I/O priority classes are implemented by the I/O scheduler, and nvme0n1 was on
  # `none`, which does no reordering and therefore ignores ioprio entirely --
  # daemonIOSchedClass would have been decorative. mq-deadline has honoured the
  # rt/be/idle classes since 5.14 (CONFIG_MQ_IOSCHED_DEADLINE=y here).
  #
  # Trade-off: mq-deadline funnels requests through one sorted dispatch queue, so
  # peak synthetic IOPS drops versus `none`. That ceiling is far above any desktop
  # or build workload, and the exchange buys real isolation between builds and the
  # desktop on a single shared NVMe. Delete this rule to go back to `none`.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="mq-deadline"
  '';

  # Protected side. session.slice is where uwsm actually puts things: Hyprland,
  # quickshell and Firefox all share wayland-wm@hyprland.desktop.service, and the
  # kitty scopes sit next to it. app.slice exists but is empty on this setup.
  systemd.slices.user = protectSlice;
  systemd.slices."user-" = protectSlice;
  systemd.services."user@" = {
    overrideStrategy = "asDropin";
    serviceConfig = {
      MemoryAccounting = true;
      MemoryLow = guiReserve;
      ManagedOOMPreference = "avoid";
    };
  };
  systemd.user.slices.session = protectSlice;

  # ---- sched_ext ----------------------------------------------------------
  # sched_ext is compiled into this XanMod kernel (/sys/kernel/sched_ext/state
  # was "disabled", i.e. available but unloaded). scx_lavd is latency-first and
  # is the closest replacement for the CFS tunables EEVDF removed in 6.6.
  # Most experimental item in this file; flip enable to false to fall straight
  # back to EEVDF without touching anything else.
  services.scx = {
    enable = true;
    scheduler = "scx_lavd";
  };
}
