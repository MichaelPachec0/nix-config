# A NixOS translation of CachyOS-Settings.
#
# CachyOS ships its tuning as an Arch package of dotfiles under /usr/lib, which
# has no NixOS equivalent, so every item here is hand-translated from the
# upstream file it mirrors. The upstream path is named above each block so a
# future reader can diff against it; upstream changes do NOT flow in
# automatically.
#
# POLICY: mirror CachyOS by default. Where this repo already carries a setting
# that disagrees, the local value stays as the incumbent and the disagreement is
# settled by measurement rather than by preference -- so those settings are
# deliberately ABSENT from this file rather than being silently overridden here.
# Each one is listed in the "deliberately not mirrored" section at the bottom
# with the reason, so an item missing from this file is a decision and not an
# oversight.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.cachyosSettings;
in {
  options.local.cachyosSettings = {
    enable =
      lib.mkEnableOption "the CachyOS-Settings mirror"
      // {
        default = true;
      };
  };

  config = lib.mkIf cfg.enable {
    # ---- usr/lib/sysctl.d/70-cachyos-settings.conf -----------------------
    # Only the keys that are BOTH upstream's and not already true here. Values
    # already matching upstream on this kernel are omitted rather than restated,
    # because a restated value looks like a decision and would hide it if the
    # kernel default later moved.
    boot.kernel.sysctl = {
      # Halves the kernel's eagerness to reclaim dentry/inode cache. Upstream's
      # rationale is that re-reading metadata is more expensive than holding it.
      # Do not set this to 0: that can produce out-of-memory conditions.
      "vm.vfs_cache_pressure" = 50;

      # Hide kernel messages below KERN_ERR from the console. Was 4 4 1 4.
      "kernel.printk" = "3 3 3 3";

      # 2 = kernel pointers in /proc are hidden from ALL users, not just
      # unprivileged ones. Was 1. A tightening, and the only security-relevant
      # line in this file.
      "kernel.kptr_restrict" = 2;

      # Deeper per-CPU backlog before the netdev receive queue drops packets.
      # Was the 1000 default.
      "net.core.netdev_max_backlog" = 4096;

      # ---- usr/lib/udev/rules.d/30-zram.rules --------------------------
      # Upstream ships 100 in its sysctl file and then raises it to 150 from a
      # udev rule the moment zram0 initialises. Every host here runs zram
      # unconditionally, so the two-step is collapsed into the settled value:
      # 150 is what a CachyOS box with zram actually ends up running, and the
      # 100 baseline only ever applies to a machine without it.
      #
      # Above 100 tells the kernel that swap IO is cheaper than filesystem IO,
      # which is true for zram and false for a disk swap. What keeps the disk
      # tier out of reach is swap PRIORITY, not this value -- see
      # zramSwap.priority below.
      #
      # Was 180 here. That was not arbitrary, but it was also never measured
      # against 150, so it is a deviation and it goes back to upstream's value
      # until an A/B says otherwise.
      "vm.swappiness" = 150;
    };

    # ---- usr/lib/systemd/zram-generator.conf ------------------------------
    # Upstream's swap-priority. The absolute number carries no meaning on its
    # own; all that matters is that zram outranks the encrypted disk swap, which
    # sits at -1. NixOS defaults this to 5, which already outranks it, so this
    # change is cosmetic alignment rather than a behaviour change -- recorded
    # here so the mirror is a real mirror and the next reader does not have to
    # rediscover that 5 and 100 rank identically against one disk tier.
    #
    # NOT mirrored from the same upstream file: zram-size. Upstream uses `ram`
    # (100%); thanatos deliberately oversubscribes to 200% against a measured
    # ~4.2x compression ratio. See nixos/thanatos/memory.nix.
    zramSwap.priority = 100;

    # ---- usr/lib/udev/rules.d/30-zram.rules ------------------------------
    # Upstream disables zswap when zram initialises, because the two stack
    # badly: zswap sits in front of the swap device and compresses pages before
    # handing them to zram, which then tries to compress them again. The second
    # pass costs CPU for essentially nothing and it also breaks zramctl's
    # accounting of what is actually stored.
    #
    # Expressed as a kernel parameter rather than upstream's udev RUN+= because
    # the parameter takes effect before any swap is set up, which removes the
    # window where zswap is live and the ordering question with
    # systemd-zram-setup entirely. Verify with
    #   cat /sys/module/zswap/parameters/enabled     -> N
    # This read Y before the change.
    boot.kernelParams = ["zswap.enabled=0"];

    # ---- usr/lib/tmpfiles.d/thp-shrinker.conf ----------------------------
    # khugepaged will collapse a region into a huge page while up to this many
    # of its 512 base pages are unpopulated. The kernel default of 511 means
    # "collapse almost anything", which on a machine backed by zram inflates
    # memory that was never touched into pages that must then be compressed.
    # 409 is upstream's value: at most 80% may be empty.
    #
    # This matters more here than on the desktops upstream targets, because this
    # host runs zram at 200% of RAM -- see nixos/thanatos/memory.nix.
    systemd.tmpfiles.rules = [
      "w! /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 409"
      # usr/lib/tmpfiles.d/coredump.conf: clear coredumps after 3 days.
      "e /var/lib/systemd/coredump - - - 3d"
      # usr/lib/tmpfiles.d/thp.conf. Already the live value on this kernel; set
      # explicitly so it survives a kernel whose default differs.
      "w! /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise"
    ];

    # ---- usr/lib/systemd/{system,user}.conf.d/00-timeout.conf ------------
    # NixOS leaves systemd's 90s stop / 90s start defaults in place. Upstream
    # cuts both hard, which is the difference between a shutdown that hangs for
    # a minute and a half on one stuck unit and one that does not.
    #
    # NOTE the start timeout is the riskier half: a unit that legitimately takes
    # longer than 15s to start now fails instead of starting slowly. If a unit
    # starts failing after this lands, give THAT unit a TimeoutStartSec rather
    # than raising the global back.
    systemd.settings.Manager = {
      DefaultTimeoutStartSec = "15s";
      DefaultTimeoutStopSec = "10s";
    };
    systemd.user.settings.Manager = {
      DefaultTimeoutStartSec = "15s";
      DefaultTimeoutStopSec = "10s";
    };

    # ---- usr/lib/systemd/journald.conf.d/00-journal-size.conf -------------
    services.journald.extraConfig = ''
      SystemMaxUse=50M
    '';

    # ---- usr/lib/systemd/system/user@.service.d/delegate.conf -------------
    # Hands the user manager its own cgroup subtree for these controllers, so
    # per-slice resource settings inside the user session are actually
    # enforceable. NixOS delegates a narrower set by default.
    #
    # This is a precondition for the memory.low / io.latency slice tree in
    # nixos/thanatos/memory.nix, not merely compatible with it: without `memory`
    # and `io` delegated, protections set on the user's own slices have nothing
    # to act on.
    systemd.services."user@" = {
      overrideStrategy = "asDropin";
      serviceConfig.Delegate = "cpu cpuset io memory pids";
    };

    # ---- usr/lib/modprobe.d/blacklist.conf --------------------------------
    # Platform watchdog timers. sp5100_tco (AMD) is loaded on thanatos and
    # iTCO_wdt is its Intel counterpart on nyx; neither is used, both keep a
    # timer armed. Upstream blacklists both.
    boot.blacklistedKernelModules = ["sp5100_tco" "iTCO_wdt"];

    # ---- usr/lib/modules-load.d/ntsync.conf -------------------------------
    # NT synchronisation primitives, used by Wine/Proton to implement Windows
    # sync objects in the kernel instead of emulating them in userspace. Built
    # as a module on this kernel (CONFIG_NTSYNC=m) and not autoloaded.
    boot.kernelModules = ["ntsync"];

    # ---- etc/security/limits.d/20-audio.conf ------------------------------
    security.pam.loginLimits = [
      {
        domain = "@audio";
        type = "-";
        item = "rtprio";
        value = "99";
      }
      {
        domain = "@audio";
        type = "-";
        item = "nice";
        value = "-11";
      }
    ];

    # ---- usr/lib/udev/rules.d/{40-hpet-permissions,99-cpu-dma-latency} ----
    # Lets the audio group hold /dev/cpu_dma_latency open, which is how a
    # userspace audio daemon asks the kernel not to enter deep C-states and so
    # bounds wakeup latency. Note the interaction with battery life: anything
    # holding this open blocks the deep idle states this laptop's runtime-PM
    # work depends on, so it is a capability, not a default -- nothing here
    # opens it.
    services.udev.extraRules = ''
      DEVPATH=="/devices/virtual/misc/cpu_dma_latency", OWNER="root", GROUP="audio", MODE="0660"
      KERNEL=="rtc0", GROUP="audio"
      KERNEL=="hpet", GROUP="audio"
    '';

    # ---- DELIBERATELY NOT MIRRORED ----------------------------------------
    #
    # Disagreements with settings this repo measured. Each stays at the local
    # value as the incumbent arm and is settled by an A/B, not by preference:
    #
    #   vm.dirty_bytes = 256M / vm.dirty_background_bytes = 64M
    #     Ours is 64M/16M. 256M is the exact value an A/B on this SSD already
    #     rejected -- it lost read p99 by ~1.4ms and took four times the
    #     swap-ins. Re-testing it against the new kernel is reasonable;
    #     adopting it unmeasured would undo a measured result.
    #
    #   60-ioschedulers.rules: kyber for NVMe
    #     Ours is adios, which is a CachyOS-kernel scheduler CachyOS's own rule
    #     predates. Both beat bfq (our previous choice) by an order of magnitude
    #     on desktop I/O stall; adios then beat kyber on durable-commit latency
    #     by 2-4x with no throughput cost, and tied elsewhere. See the scheduler
    #     block in nixos/thanatos/memory.nix for the numbers.
    #     The new kernel also offers `adios`, which did not exist before and
    #     belongs in the same comparison.
    #
    #   zram-generator: zram-size = ram
    #     Ours is 200% of RAM, deliberately oversubscribed against a measured
    #     ~4.2x compression ratio.
    #
    # Not mirrored for reasons that are NOT open questions:
    #
    #   10-limits.conf: DefaultLimitNOFILE 2048:2097152 / 1024:1048576
    #     Both managers here already run 524288:524288. Upstream's soft limits
    #     are LOWER, and the user-manager soft limit of 1024 is the specific
    #     value behind a documented failure on this hardware: the user
    #     dbus-broker costs 2 fds per peer and dies on EMFILE, taking the
    #     graphical session down to the greeter. Adopting upstream here would
    #     be a knowing regression, so it is refused rather than deferred.
    #
    #   fs.file-max = 2097152
    #     Already effectively unlimited here (2^63-1). Upstream's value is a
    #     ceiling, not a floor; setting it would only lower it.
    #
    #   kernel.nmi_watchdog = 0, 20-audio-pm.rules, 50-sata.rules
    #     TLP already owns all three and expresses the audio one AC/battery
    #     aware, which the udev rule also does but less legibly. Two mechanisms
    #     writing one knob is how a setting becomes unexplainable.
    #
    #   kernel.unprivileged_userns_clone = 1, vm.page-cluster = 0,
    #   vm.dirty_writeback_centisecs = 1500
    #     Already true on this kernel/config. Restating them would hide a future
    #     change in the underlying default.
    #
    #   69-hdparm.rules (no rotational disks), 71-nvidia.rules (nyx only, and
    #   the nvidia stack is not migrated yet), dns.conf, X11 touchpad, the GDM
    #   logo schema, iw-set-regdomain, debuginfod, pci-latency: not applicable
    #   to a Wayland/systemd-resolved laptop with no PCI sound card.
  };
}
