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

    # Bound writeback by bytes, not by percent-of-RAM. Setting *_bytes zeroes
    # the matching *_ratio; they are mutually exclusive, so do not reintroduce
    # vm.dirty_ratio here.
    #
    # 64M/16M measured against the previous 256M/64M and against the 20%/10%
    # defaults, under a bulk writer plus 6 GiB of actively-touched anon (the
    # workload that motivated this: a build under memory pressure, where reclaim
    # and swap compete with writeback). 64M won read p99 by ~1.4ms and took a
    # quarter of the swap-ins, costing ~7% write throughput. Latency is the
    # right side of that trade here for the same reason it is for bfq below.
    # The defaults arm hit a position confound and is still unmeasured, so it
    # remains an open option.
    #
    # Do not judge a re-test by PSI io.full: run-to-run spread swamped the gap
    # between arms. Read p99 under load is what separates them. Both values are
    # live-tunable, so no rebuild is needed; writing either pair zeroes the
    # other, so read BOTH back:
    #   sysctl -w vm.dirty_bytes=67108864 vm.dirty_background_bytes=16777216
    #   sysctl -w vm.dirty_ratio=20 vm.dirty_background_ratio=10   # defaults
    #
    # Note powertop reports "Bad: VM dirty ratio" here. That is a false
    # positive: it reads vm.dirty_ratio, which is 0 precisely BECAUSE the byte
    # limits are in force. Never let `powertop --auto-tune` near this -- it
    # would set the ratio, silently zero the byte limits, and undo the bound.
    "vm.dirty_bytes" = 64 * 1024 * 1024;
    "vm.dirty_background_bytes" = 16 * 1024 * 1024;

    # THP is madvise-only, so proactive compaction only spends latency building
    # huge pages nothing asked for. compact_stall was ~10k before this.
    "vm.compaction_proactiveness" = 0;
  };

  # ---- zram ---------------------------------------------------------------
  # disksize is virtual: real consumption is the compressed size, and the
  # measured ratio here is ~4.2x (3.77G orig -> 922M compressed), so 200% of RAM
  # of disksize costs under half of RAM even when fully filled. Oversubscribing
  # is the point -- at 50% zram filled and spilled ~8G onto the NVMe swap, which
  # is the slow tier this whole file exists to avoid.
  zramSwap.memoryPercent = lib.mkForce 200;

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

  # BFQ is a module (CONFIG_IOSCHED_BFQ=m), so it must be loaded before udev can
  # select it below.
  boot.kernelModules = ["bfq"];

  # bfq, measured against none / mq-deadline / kyber under a nix-build-shaped
  # load. It wins every latency metric by 2-6x and its worst round still beats
  # the others' medians; mq-deadline produced 534ms fsync stalls, the exact
  # shape that hung Firefox's Quota Manager until its watchdog killed it. The
  # cost is bulk throughput -- a cold Firefox launch during a build is 1.7x
  # slower than under mq-deadline -- and that trade is accepted deliberately,
  # because this machine's complaint is stutter during builds, not launch time
  # during builds. Set this back to `none` to undo it.
  #
  # BFQ TUNING WAS MEASURED AND REJECTED, do not reach for it: slice_idle=0
  # (the standard "SSDs do not need idling" advice), slice_idle_us=0 and
  # low_latency=0 each cost 1.3-2.9x on reads, and strict_guarantees=1 explodes
  # the tails. Every one of them bought fsync p99 at the expense of reads, which
  # is the wrong direction for desktop feel. Also not worth revisiting: a
  # read_ahead_kb bump, flat across 128-2048 because max_hw_sectors_kb is 128
  # here and large read()s bypass readahead entirely.
  #
  # bfq also keeps the reason mq-deadline was chosen before it -- it honours the
  # rt/be/idle ioprio classes, so nix.daemonIOSchedClass above is not decorative
  # the way it was under `none` -- and adds cgroup io.weight, which mq-deadline
  # does not implement and iocost is not active to provide.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="bfq"
  '';

  # Build width. Both of these defaulted to `auto`, which on this 8C/16T part
  # means max-jobs=16 and cores=0 ("use everything") -- i.e. up to 16 concurrent
  # derivations each free to spawn 16 compiler threads, ~256 runnable tasks.
  #
  # SCHED_IDLE above rations CPU *time* correctly at that width, but two costs it
  # cannot touch scale with the thread count and are what the desktop actually
  # feels:
  #   - L3 is 2x4M, one per 4-core CCX (cpu0-7 and cpu8-15 -- verify with
  #     cache/index3/shared_cpu_list, NOT lscpu's aggregate "8 MiB"), and Zen 2
  #     does not share it across CCXs. A 256-thread compile refills both from
  #     DRAM continuously, so an interactive thread pays a cold cache on every
  #     wakeup no matter how promptly it is scheduled.
  #   - use-cgroups is off, so all builders share the ONE MemoryHigh above rather
  #     than getting a budget each: at 16 jobs that is ~512M apiece before the
  #     cgroup starts forcing reclaim, versus ~2G at 4. Reclaim here compresses
  #     into zram on these same cores, so overshoot is paid in desktop latency.
  #     (Unverified as the trigger -- nix-daemon.service's memory.events `high`
  #     counter during a build is what would confirm it; the counter resets when
  #     the daemon restarts, which a rebuild does.)
  #
  # 4x4 keeps the product at 16, one runnable thread per hardware thread: builds
  # can still occupy the entire CPU, they just cannot oversubscribe it. Note this
  # is a *default*, not a ceiling -- `cores` only sets $NIX_BUILD_CORES, so a
  # derivation that hardcodes its own -j still overshoots.
  nix.settings = {
    max-jobs = 4;
    cores = 4;
  };

  # Protected side. The desktop working set spans THREE branches under
  # user@.service and all of them have to be granted, because memory.low is
  # only effective where every ancestor also grants it -- systemd derives a
  # slice's parent from its dashed name, so app-graphical.slice sits under
  # app.slice and background-graphical.slice under background.slice, and
  # skipping the intermediate level would silently zero the protection:
  #
  #   session.slice                  -- the compositor unit itself
  #                                     (wayland-wm@hyprland.desktop.service)
  #                                     plus the kitty scopes beside it.
  #   app.slice
  #     app-graphical.slice          -- one scope per application.
  #   background.slice
  #     background-graphical.slice   -- quickshell (the bar) and the watermark,
  #                                     launched with app-run -s b.
  #
  # Both -graphical branches were empty until launches were routed through the
  # uwsm runner -- every GUI process used to be a fork() of the compositor and
  # therefore lived inside its unit (see features/hm/wayland/app-run.nix).
  # Now that Firefox/kitty/keepassxc and the bar get their own scopes out
  # there, protecting session.slice alone would leave the applications
  # themselves as first reclaim/oomd candidates, i.e. exactly backwards.
  #
  # All branches claim the same guiReserve rather than splitting it: memory.low
  # is best-effort and the real ceiling is what user@.service grants, which the
  # kernel then distributes proportionally between whichever children are
  # actually claiming. Splitting would just under-protect whichever side happens
  # to be busy.
  # I/O latency protection for the desktop, the half ionice alone cannot give.
  #
  # io.latency is set on the group to PROTECT, not the one to punish: the kernel
  # watches this group's completion latency and, when it exceeds the target,
  # throttles peer cgroups that have no target of their own. system.slice (where
  # nix-daemon builds) is such a peer, so a build gets squeezed exactly when the
  # desktop starts suffering and not before -- unlike a hard IOReadBandwidthMax,
  # which would slow builds even on an idle machine.
  #
  # Target 10ms: this drive answers a cold 4K read in ~600us and a durable commit
  # in ~3ms, so 10ms is ~16x headroom over healthy operation and still trips well
  # before a human notices. Raise toward 25-50ms if builds crawl while the
  # desktop is idle; lower only if video playback during a build still breaks up.
  #   cat /sys/fs/cgroup/user.slice/io.latency     -> "259:0 target=10000"
  #   cat /sys/fs/cgroup/system.slice/io.pressure  -> "some" rises when throttled
  #
  # Device is the physical nvme, not the dm-crypt mapper: bio cgroup association
  # is preserved down through dm, and 259:0 is where the real queue contention
  # happens (io.stat in these cgroups accounts both 254:x and 259:0).
  systemd.slices.user =
    protectSlice
    // {
      sliceConfig =
        protectSlice.sliceConfig
        // {
          IODeviceLatencyTargetSec = "/dev/nvme0n1 10ms";
        };
    };
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
  systemd.user.slices.app = protectSlice;
  systemd.user.slices.background = protectSlice;
  # The two -graphical slices are shipped by the uwsm package (symlinked into
  # /etc/systemd/user), so these are drop-ins over existing units rather than
  # fresh ones -- same asDropin strategy the rest of this file uses.
  systemd.user.slices.app-graphical = protectSlice;
  systemd.user.slices.background-graphical = protectSlice;

  # ---- sched_ext ----------------------------------------------------------
  # scx_flash -m all, picked by paired per-round measurement against EEVDF and
  # six other scx schedulers. It beats EEVDF on cold launch, wakeup p99 under
  # build (22us vs 747us) and runqueue wait, and costs ~95ms on launch during a
  # build. beerland, cake, cosmos, flow and p2dq were each disqualified on a
  # reproduced regression; rusty never attached at all (its own bug).
  #
  # Traps this file has already fallen into:
  #   - scx_lavd, which this shipped before, IS the "Firefox was snappier
  #     before" regression: ~450ms on every cold launch. Do not restore it on
  #     the strength of its latency-first description.
  #   - --performance made lavd WORSE, not better, so the intuitive "pin it to
  #     performance on AC" fix is backwards. An ac-responsiveness.nix that did
  #     exactly that was written and deleted on those numbers.
  #   - NEVER add -f/--cpufreq: +41% cold launch, the largest regression
  #     measured. Scheduler-driven frequency selection ramps slower than
  #     schedutil's own, and a cold launch is the burst that needs the ramp.
  #   - Wakeup latency does NOT govern launch time. Every scx scheduler beats
  #     EEVDF on wakeup tail by 20-30x and several still launch Firefox slower.
  #   - The CachyOS wiki's flash profiles ("-m performance -w -C 0") do not
  #     apply to scx_flash 1.1.2 as packaged in nixpkgs: no -w, no -C, and it
  #     refuses to start if given them.
  #
  # -m takes auto|turbo|performance|powersave|all|none; on this 8-core Zen 2
  # part `all` is near a no-op for latency but consistently halved the
  # throughput cost versus the auto default.
  services.scx = {
    enable = true;
    scheduler = "scx_flash";
    extraArgs = ["-m" "all"];
  };

  # Retry hard, because attaching a sched_ext scheduler is inherently racy and
  # the packaged unit gives up almost immediately.
  #
  # Attaching walks every existing task and cgroup, allocating BPF local storage
  # for each in a tight loop. Anything creating a task or a cgroup during that
  # walk can make one of those allocations return NULL, which the scheduler
  # reports as -ENOMEM and the kernel treats as fatal. Nothing about the
  # scheduler or its flags is wrong when this happens and no tunable prevents
  # it; boot lost 3 attaches out of 4. The stock unit is what made a lost round
  # permanent: Restart=on-failure with no RestartSec retries in under a second,
  # and StartLimitBurst=2 inside 30s puts both attempts inside the same storm.
  #
  # 12 attempts 5s apart covers ~60s against a boot storm that settles by ~35s,
  # and stays bounded so a genuinely broken scheduler (a kernel upgrade
  # outrunning the scx package) still gives up instead of respawning forever.
  #
  # Do NOT "fix" this by ordering scx after some other unit. waydroid-container
  # was the obvious suspect and is not the cause -- restarting it under a live
  # attach never reproduced the failure. Any task creation anywhere will do it.
  systemd.services.scx = {
    startLimitIntervalSec = lib.mkForce 300;
    startLimitBurst = lib.mkForce 12;
    serviceConfig.RestartSec = 5;
  };
}
