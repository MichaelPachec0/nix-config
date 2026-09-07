{
  config,
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
  # not have been affected at all. The cross-tree knobs are SCHED_IDLE below and
  # the user.slice/system.slice weights further down -- those two slices ARE
  # siblings, under the root cgroup.
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
  # left alone.
  #
  # CURRENTLY INERT, kept for the day the elevator changes back. An I/O
  # scheduler has to look at the ioprio class for this to do anything, and the
  # one selected below does not. Checked against the kernel source rather than
  # assumed -- occurrences of ioprio in block/:
  #
  #   adios.c 0    kyber-iosched.c 0    mq-deadline.c 18
  #
  # bfq honoured it too, which was its one real advantage, and bfq lost by 13x
  # on desktop I/O stall. So the class is priced at zero today. The
  # work-conserving I/O equivalent of the slice CPUWeights below would be
  # blk-iocost (io.weight), which sits above the elevator and so is unaffected
  # by this; it is not enabled here, and given that io.latency and ioprio have
  # both turned out to buy nothing on this machine it should be measured with
  # ab-matrix's io-matrix.sh before being adopted rather than switched on
  # because the mechanism sounds right.
  nix.daemonIOSchedClass = "idle";

  # adios. CONFIG_MQ_IOSCHED_ADIOS=y, so unlike bfq (CONFIG_IOSCHED_BFQ=m) it
  # needs no boot.kernelModules entry. It is a CachyOS-kernel scheduler and does
  # not exist on stock nixpkgs kernels, so this line and nixos/thanatos/kernel.nix
  # move together.
  #
  # THIS REPLACES BFQ, and bfq was itself a recorded decision, so the reason
  # matters. That choice came from an A/B whose load and probe both ran inside
  # one privileged cgroup: the desktop's own I/O was never in the picture, so it
  # measured fio's read latency against a synthetic burner rather than a desktop
  # against a build. Re-measured with the probe running as the user in
  # user.slice and the load as real nix builds under nix-daemon, 48 cells, bfq
  # loses by an order of magnitude:
  #
  #   desktop us stalled on I/O per 210s window, median of 16 cells each
  #     kyber   232264      adios   263490      bfq  3065494
  #   the probe's own read p99
  #     kyber    21403us    adios    20369us    bfq   244345us
  #
  # bfq is thus excluded on evidence. Choosing between the two survivors took a
  # second, I/O-bound matrix (see io-matrix.sh): 24 cells x 3 reps of fio in
  # system.slice against the same probe in user.slice, across three load shapes.
  # Sequential-read and random-mixed came out a genuine tie. Durable-commit --
  # small writes with an fsync every 16, the shape that historically produced
  # 534ms stalls here and hung Firefox's Quota Manager -- did not:
  #
  #                             adios       kyber
  #     desktop read p99      4549us     17453us    3.8x, resolvable
  #     desktop wakeup p99.9   269us       616us    2.3x, resolvable
  #     load commit p99      21758us     70779us    3.3x
  #     load commit p99.9    42467us    190054us    4.5x
  #     write throughput    207 MB/s    143 MB/s    +45%
  #
  # Only the first two clear a |median| > sd bar on their own. The weight is in
  # the agreement: all 9 informative metrics favour adios and none favour kyber,
  # which is p ~= 0.004 by sign test. There is also no trade to price, since
  # adios leads on throughput as well as on latency.
  #
  # WHY NOT KYBER, given the first matrix showed adios with a worse tail (16
  # cells spanning 136ms-3.10s against kyber's 131-608ms). Both adios outliers
  # were sched=eevdf AND cpuw=off, and this file now ships scx_flash with
  # 1000/20 slice weights. Restricted to the configuration actually in use, the
  # two are indistinguishable on every metric (n=4, all noise). The tail
  # argument was real for the machine as configured then, and stopped applying
  # the moment those two arms were dropped.
  #
  # KNOWN WEAKNESS in the above, recorded so it is not rediscovered as news: the
  # two tied profiles were partly served from page cache (53% and 40%, caught by
  # the harness's own device counters), so their ties are the weakest evidence
  # in the set. fsync reached the device unimpeded and is the one that resolved.
  # io-matrix.sh has since been fixed to use an 80G working set and drop caches
  # per cell; a re-run would firm up the ties, not the fsync result.
  #
  # What is NOT lost by leaving bfq: it honoured the rt/be/idle ioprio classes,
  # which is what made nix.daemonIOSchedClass above non-decorative. Neither
  # adios nor kyber implements ioprio classes, so that setting is now inert for
  # the queue and earns its keep only through the daemon's own SCHED_IDLE and
  # the slice weights below. Accepted cost: every cell of both matrices ran with
  # the same daemon settings, so it is already priced into the numbers.
  #
  # BFQ TUNING WAS MEASURED AND REJECTED and is now moot, but keep it recorded
  # so nobody re-runs it: slice_idle=0, slice_idle_us=0 and low_latency=0 each
  # cost 1.3-2.9x on reads, and strict_guarantees=1 explodes the tails. Also
  # not worth revisiting: a read_ahead_kb bump, flat across 128-2048 because
  # max_hw_sectors_kb is 128 here and large read()s bypass readahead entirely.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="adios"
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
    cores = 6;
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
  # NO IODeviceLatencyTargetSec here, and that is a measured removal rather than
  # an oversight.
  #
  # The mechanism is sound on paper: io.latency set on the group to PROTECT
  # makes the kernel throttle peer cgroups with no target of their own once this
  # group misses its target, so a build is squeezed exactly when the desktop
  # suffers and not before. It was carried at "/dev/nvme0n1 10ms".
  #
  # It was a factor in both matrices and did nothing in either: noise on I/O
  # stall, CPU stall, memory stall, longest stall and wakeup p99.9, a dead-even
  # 13-vs-12 split of the 25 dropped frames in the build matrix, and still noise
  # at n=36 in the I/O-bound one under a genuine 376 MB/s of sustained writes.
  #
  # THE REASON IS STRUCTURAL, not a matter of picking a better target, so do not
  # reach for this again with a lower number. From check_scale_change() in
  # block/blk-iolatency.c, on the path that would throttle a peer:
  #
  #     /*
  #      * Sometimes high priority groups are their own worst enemy, so
  #      * instead of taking it out on some poor other group that did 5%
  #      * or less of the IO's for the last summation just skip this
  #      * scale down event.
  #      */
  #     samples_thresh = lat_info->nr_samples * 5;
  #     samples_thresh = max(1ULL, div64_u64(samples_thresh, 100));
  #     if (iolat->nr_samples <= samples_thresh)
  #             return;
  #
  # The protected cgroup must have issued MORE THAN 5% of the I/O in the last
  # summation or the throttle is skipped outright. A desktop being crushed by a
  # build or a copy is by definition the minority producer: in the I/O matrix
  # the probe did about 5 IOPS against fio's ~27000, which is 0.02% against a 5%
  # floor -- three orders of magnitude short. io.latency is built for a
  # protected group that is itself a substantial producer, a database container
  # against a backup job, and cannot express "this tiny reader matters most".
  #
  # A second, independent reason it never fired: latency_sum_ok() compares the
  # window MEAN against the target, and the probe's read p99 was 4.5-9.4ms under
  # either surviving scheduler, so the mean never reached 10ms regardless.
  #
  # Left off because it is not a knob that was set wrong, it is a mechanism that
  # does not apply here. The cross-tree lever that does work is CPUWeight on the
  # slices above.
  # CPUWeight 1000 against system.slice's 20 -- see the block above for why the
  # 50:1 split and what it bought. Kept here rather than in that block so the
  # protectSlice memory settings and the CPU weight for the same unit stay in
  # one place.
  systemd.slices.user =
    protectSlice
    // {
      sliceConfig =
        protectSlice.sliceConfig
        // {
          CPUAccounting = true;
          CPUWeight = 1000;
        };
    };
  # ---- CPU weight across the two subtrees ---------------------------------
  # user.slice and system.slice are siblings under the root cgroup, so weighting
  # them is the cross-tree CPU control that the nix-daemon comment above says
  # does not exist at service level. Both sat at the default 100 until now, i.e.
  # this lever had never been pulled.
  #
  # It turned out to be the largest GUI-relevant effect in the 48-cell matrix,
  # and one that only showed up once frame misses were counted rather than
  # averaged. Of 25 missed 120Hz frame deadlines across the whole run, 24 landed
  # on the weight=100/100 arm and 1 on this one; 12 of the 13 cells that dropped
  # any frame were the default arm (p ~= 0.003, sign test over 13 cells). The
  # paired-median test reported it as "noise" on every stall metric because most
  # cells drop zero frames, so the median difference is structurally zero. The
  # corroborating signals: longest single stall 2ms here against 4ms at the
  # default, and psi_cpu missing resolvability by 0.4%.
  #
  # 1000/20 is a 50:1 split, chosen deliberately over something timid: a weight
  # ratio only bites while both sides are runnable, and a 2:1 split would have
  # landed inside the noise and proven nothing either way. On an idle desktop it
  # costs nothing at all, because weights do not cap anything -- system.slice
  # gets the whole machine when user.slice is not asking.
  #
  # Nothing in system.slice is latency-critical enough to mind: those units are
  # event-driven and near-idle in CPU terms, and the one CPU-heavy resident,
  # nix-daemon, is already SCHED_IDLE by choice.
  systemd.slices.system = {
    overrideStrategy = "asDropin";
    sliceConfig = {
      CPUAccounting = true;
      CPUWeight = 20;
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
  # OFF, on measurement, in favour of EEVDF-BORE. Everything above stays
  # recorded because it was all true against plain EEVDF and would apply again
  # the moment scx is reconsidered.
  #
  # WHAT CHANGED: the earlier comparison was flash against EEVDF on a kernel
  # with no BORE in it. Re-run on linux-cachyos-bore-lto, three arms in one
  # boot -- flash, EEVDF+BORE, EEVDF alone -- 38 cells, 12 complete
  # repetitions, every arm re-verified after its measurement window. The three
  # distributions do not overlap at all:
  #
  #                    flash              bore
  #     wake p99      973-1000us       248- 583us    bore 2.6x better
  #     wake p99.9  1058-1074us       1150-1324us    flash better
  #     psi_cpu      2.41M-5.55M       0.80M-1.34M   bore 2.4x better
  #
  # scx_flash flattens the whole wakeup distribution: its p99 and p99.9 sit
  # 80us apart with a 15us spread across 13 cells, so nearly every wakeup costs
  # about a millisecond. BORE is 2.6x faster typically and gives part of it back
  # at the extreme.
  #
  # The tie-break is the frame budget, not the other arm. At 120Hz that is
  # 8333us, and flash's 1064us against bore's 1220us are both about 7x under it
  # -- that gap cannot be felt. A 2.6x difference in what a wakeup usually
  # costs applies to every wakeup there is, and the 2.4x lower desktop CPU
  # stall says the same thing independently. Frame misses tied at 1-2 per arm
  # and no 60Hz deadline was missed in any of the 38 cells; build throughput
  # was identical at 12 compilers alive per window.
  #
  # HONEST LIMIT: flash really does win the extreme tail, and this is a
  # judgement that the common case matters more, not a clean sweep. Re-run
  # ab-matrix/sched-ab.sh if that judgement is ever in doubt; it toggles all
  # three arms at runtime and needs no rebuild.
  #
  # Turning this back on also means undoing the sched_bore sysctl below: BORE
  # governs nothing while scx owns the tasks, so leaving both on would be a
  # configuration that measures as flash while reading as bore.
  services.scx.enable = false;

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
  # Kept for the day scx comes back, but MUST be guarded on services.scx.enable.
  #
  # An unguarded `systemd.services.scx = { ... }` DEFINES the unit whether or not
  # the scx module is enabled. With enable = false the module contributes no
  # ExecStart, so these three overrides became the whole unit: a [Service]
  # section holding RestartSec and nothing to run. systemd rejects that with
  # "Unit scx.service has a bad unit file setting" and switch-to-configuration
  # fails the whole activation. The comment this replaces claimed it "costs
  # nothing while the unit is not started"; that was wrong, and it cost a failed
  # rebuild.
  #
  # The overrides themselves are the entire fix for the attach race described
  # above, so they stay rather than being deleted and rediscovered.
  systemd.services.scx = lib.mkIf config.services.scx.enable {
    startLimitIntervalSec = lib.mkForce 300;
    startLimitBurst = lib.mkForce 12;
    serviceConfig.RestartSec = 5;
  };

  # BORE on the fair class. The bore kernel already defaults this to 1, so this
  # is a statement of intent rather than a change: it makes the dependency on
  # nixos/thanatos/kernel.nix explicit, and it fails loudly rather than silently
  # if the kernel is ever swapped for one without BORE.
  #
  # Measured against plain EEVDF in the same boot, same load, 12 paired
  # repetitions: wakeup p99 377us against 597us, wakeup p99.9 1220us against
  # 1809us. Both resolvable by a wide margin, so BORE earns its place on the
  # fair class independently of the scx decision above.
  boot.kernel.sysctl."kernel.sched_bore" = 1;
}
