{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
} @ args: let
  # Root-only bridge: ryzen_monitor reads the SMU PM table (needs root + the
  # ryzen_smu module) and streams influx line-protocol frames over a named pipe
  # (continuously, without closing between frames). QuickShell watches regular
  # files, not pipes, so we split the stream into whole frames and republish the
  # latest one atomically as a world-readable regular file that the RyzenSmuStats
  # provider polls.
  # Checked python source: mypy --strict + unittest run at build time; a type
  # error or failing test fails the build. See
  # docs/superpowers/specs/2026-07-05-thinkfan-ryzen-smu-fan-control-design.md.
  ryzenSmuBridgeSrc = pkgs.runCommand "ryzen-smu-bridge-src" {
    nativeBuildInputs = [pkgs.python3 pkgs.mypy];
  } ''
    cp ${./ryzen-smu-bridge/fanbridge.py} fanbridge.py
    cp ${./ryzen-smu-bridge/main.py} main.py
    cp ${./ryzen-smu-bridge/test_fanbridge.py} test_fanbridge.py
    mypy --strict fanbridge.py main.py test_fanbridge.py
    python3 -m unittest test_fanbridge -v
    install -d "$out"
    cp fanbridge.py main.py "$out/"
  '';
  # Single merged service: republishes the SMU frame for Quickshell AND writes
  # /run/thinkfan/temp for thinkfan. ryzen_monitor must be on PATH.
  ryzenSmuBridge = pkgs.writeShellApplication {
    name = "ryzen-smu-bridge";
    runtimeInputs = [pkgs.python3 pkgs.playground.ryzen-monitor-ng pkgs.coreutils];
    text = ''exec python3 ${ryzenSmuBridgeSrc}/main.py "$@"'';
  };
  fanMode = pkgs.writeShellApplication {
    name = "fan-mode";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      mode="''${1:-}"
      [ -w /run/thinkfan/mode ] || { echo "fan-mode: ryzen-smu-bridge not running" >&2; exit 1; }
      case "$mode" in
        perf|quiet) printf '%s\n' "$mode" > /run/thinkfan/mode ;;
        auto)       : > /run/thinkfan/mode ;;
        *) echo "usage: fan-mode perf|quiet|auto" >&2; exit 2 ;;
      esac
      echo "fan-mode: ''${mode} (clears on AC state change)"
    '';
  };

  # thinkfan curves. quietLevels = today's curve (fed control = ema - 9 by the
  # bridge, so quiet is unchanged). perfLevels = aggressive curve on the real
  # cpu_thm scale (bridge offset 0); disengage at 78. Each row is [level low high];
  # thinkfan needs low_k < high_{k-1} (validCurve enforces this at build time).
  quietLevels = [
    [ 0 0 55 ]
    [ 2 48 66 ]
    [ 4 60 76 ]
    [ 5 70 84 ]
    [ 7 78 90 ]
    [ "level disengaged" 88 32767 ]
  ];
  perfLevels = [
    [ 0 0 50 ]
    [ 2 44 55 ]
    [ 3 49 60 ]
    [ 4 54 64 ]
    [ 5 58 68 ]
    [ 6 62 73 ]
    [ 7 67 78 ]
    [ "level disengaged" 76 32767 ]
  ];
  mkThinkfanYaml = name: levels: let
    fmtLevel = l: let
      lvl = builtins.elemAt l 0;
      lvlStr = if builtins.isInt lvl then builtins.toString lvl else lvl;
      lo = builtins.toString (builtins.elemAt l 1);
      hi = builtins.toString (builtins.elemAt l 2);
    in "- - ${lvlStr}\n  - ${lo}\n  - ${hi}";
    body = lib.concatStringsSep "\n" (map fmtLevel levels);
  in pkgs.writeText name ''
    fans:
    - tpacpi: /proc/acpi/ibm/fan
    sensors:
    - hwmon: /run/thinkfan/temp
    levels:
    ${body}
  '';
  # low_k < high_{k-1} for every adjacent pair.
  validCurve = levels: let
    lows = map (l: builtins.elemAt l 1) levels;
    highs = map (l: builtins.elemAt l 2) levels;
    n = builtins.length levels;
    idxs = builtins.genList (i: i + 1) (n - 1);
  in builtins.all (k: (builtins.elemAt lows k) < (builtins.elemAt highs (k - 1))) idxs;
  quietYaml = mkThinkfanYaml "thinkfan-quiet.yaml" quietLevels;
  perfYaml = mkThinkfanYaml "thinkfan-perf.yaml" perfLevels;
  fanCurveApply = pkgs.writeShellApplication {
    name = "fan-curve-apply";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd ];
    text = ''
      mode="$(cat /run/thinkfan/mode-resolved 2>/dev/null || echo quiet)"
      case "$mode" in
        perf) src=${perfYaml} ;;
        *)    src=${quietYaml} ;;
      esac
      tmp="$(mktemp /run/thinkfan/active.yaml.XXXXXX)"
      cp "$src" "$tmp"
      mv -f "$tmp" /run/thinkfan/active.yaml
      # thinkfan may not be up yet during boot races; ignore a failed reload.
      systemctl reload thinkfan.service || true
    '';
  };

  # Custom XKB data dir: base xkeyboard-config plus a `cadet:parens` OPTION that
  # remaps the spare F13-F16 keycodes (emitted by the space-cadet keys in
  # services.kanata below) to UNSHIFTED paren/brace. It MUST be an option, not a
  # layout: the evdev rules merge symbols as `pc+us+inet(evdev)+<options>`, and
  # inet(evdev) claims FK13-FK24 -- so only the trailing option slot can override
  # them (a layout-slot override loses to inet, which is why the earlier
  # us_cadet layout compiled but produced XF86Tools on those keys). This single
  # dir feeds BOTH Hyprland (XKB_CONFIG_ROOT) and the TTY console (ckbcomp) via
  # services.xserver.xkb.dir below. Verified with `xkbcli compile-keymap`.
  # See docs/superpowers/specs/2026-07-10-cadet-paren-brace-wm-chords-design.md
  cadetXkbSymbols = pkgs.writeText "xkb-cadet-symbols" ''
    partial xkb_symbols "parens" {
        key <FK13> { [ parenleft  ] };
        key <FK14> { [ parenright ] };
        key <FK15> { [ braceleft  ] };
        key <FK16> { [ braceright ] };
    };
  '';
  cadetXkbRule = pkgs.writeText "xkb-cadet-rule" ''

    ! option = symbols
      cadet:parens = +cadet(parens)
  '';
  cadetXkbDir = pkgs.runCommand "xkb-cadet" {} ''
    mkdir -p "$out/share/X11/xkb"
    cp -rL ${pkgs.xkeyboard_config}/share/X11/xkb/. "$out/share/X11/xkb/"
    chmod -R u+w "$out/share/X11/xkb"
    cp ${cadetXkbSymbols} "$out/share/X11/xkb/symbols/cadet"
    cat ${cadetXkbRule} >> "$out/share/X11/xkb/rules/evdev"
  '';

  # Cadet double-tap window (ms): how long a single ( / ) waits to see whether a
  # second tap turns it into { / }. Lower = snappier ( / ); too low makes the
  # { / } double-tap hard to trigger. One knob for both cadet keys on both
  # keyboards (the kanata `tap-dance` timeout in services.kanata below).
  cadetDoubleTapMs = 150;

  # Realtime scheduling for the kanata input daemons. kanata grabs the keyboard
  # (EVIOCGRAB) and must re-emit every event immediately; its tap-hold/tap-dance
  # decisions are time-based, so being descheduled skews those timers and lets
  # buffered kernel auto-repeats flush in a burst -- surfacing as stuck keys and
  # duplicated characters, WORSE UNDER LOAD. At the module default (SCHED_OTHER,
  # nice 0) that is exactly what happens: /proc/<pid>/schedstat measured ~2x more
  # runqueue-wait than on-CPU time on this (35W-capped, frequently loaded) APU.
  # SCHED_FIFO makes kanata preempt every normal task. Any RT priority beats
  # SCHED_OTHER; 50 is a polite value -- kanata blocks on read between events and
  # uses negligible CPU, so it cannot starve audio/pipewire. The stock module
  # sets RestrictRealtime=true (and filters @resources), which only blocks the
  # *process* from changing its own policy; systemd still applies CPUScheduling*
  # from PID1 before those take effect. Flip RestrictRealtime off anyway so the
  # combination is unambiguous across systemd versions.
  kanataRtSched = {
    CPUSchedulingPolicy = "fifo";
    CPUSchedulingPriority = 50;
    RestrictRealtime = lib.mkForce false;
    # The LIBINPUT_IGNORE_DEVICE udev rule below makes Hyprland ignore the raw
    # internal keyboard entirely, so kanata's uinput device is the ONLY keyboard
    # the session sees. That means if kanata ever exits and stays dead, the
    # laptop keyboard is invisible in the Wayland session (a TTY still works --
    # the kernel VT bypasses libinput). The stock module sets Restart=no, so a
    # crash would orphan the keyboard; force Restart=always so kanata always
    # comes back and keeps owning the device. A clean stop during nixos-rebuild
    # activation is not an unexpected exit, so this does not fight the switch.
    Restart = lib.mkForce "always";
  };
in {
  imports = [
    ./tlp.nix
    ./gaming.nix
  ];
  config = {
    assertions = [
      {
        assertion = validCurve quietLevels;
        message = "thinkfan quietLevels: each level low must be below the previous level high";
      }
      {
        assertion = validCurve perfLevels;
        message = "thinkfan perfLevels: each level low must be below the previous level high";
      }
    ];
    nixpkgs.overlays = [
      # TODO: make sure to change this!
      (self: super: {
        thinkfan = self.master.thinkfan;
      })
    ];

    boot.kernelParams = [
      "mitigations=off"
      "pcie_aspm=force"
      # "pcie_aspm.policy=powersupersave"
    ];
    # AMD Zen CPU monitoring

    # Disable generic monitoring
    boot.blacklistedKernelModules = [
      "k10temp"
    ];
    boot.extraModulePackages = with config.kernel.mod.kernelPkg; [
      ryzen-smu
      zenpower
    ];
    boot.loader.systemd-boot.consoleMode = lib.mkForce "max";
    environment.systemPackages = with pkgs; [
      ryzenadj
      playground.ryzen-monitor-ng
      amdgpu_top
      amdctl
      radeontools
      pixiecore
      fanMode
    ];
    # Publish SMU metrics (temps + power/limits) for the QuickShell system popup.
    # Falls back gracefully: if this unit is down the file goes stale and the
    # popup reverts to its lm_sensors group.
    systemd.services.ryzen-smu-bridge = {
      description = "Ryzen SMU -> Quickshell influx + thinkfan temp bridge";
      wantedBy = ["multi-user.target"];
      after = ["systemd-modules-load.service"];
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "main";
        WatchdogSec = 15;
        ExecStart = lib.getExe ryzenSmuBridge;
        Restart = "always";
        RestartSec = 5;
        RuntimeDirectory = ["ryzen-monitor" "thinkfan"];
        RuntimeDirectoryMode = "0755";
        LogLevelMax = "err";
      };
    };
    systemd.services.thinkfan = {
      after = ["ryzen-smu-bridge.service"];
      requires = ["ryzen-smu-bridge.service"];
      # Read a mutable curve that the fan-curve unit swaps at runtime, instead of
      # the immutable store path the module sets. Seed quiet-if-missing so thinkfan
      # always starts with a valid curve (a live perf curve survives a thinkfan-only
      # restart because active.yaml persists in the bridge's RuntimeDirectory).
      environment.THINKFAN_ARGS = lib.mkForce "-c /run/thinkfan/active.yaml -b0 -s2";
      serviceConfig.ExecStartPre = [
        "${pkgs.bash}/bin/bash -c 'test -f /run/thinkfan/active.yaml || ${pkgs.coreutils}/bin/cp ${quietYaml} /run/thinkfan/active.yaml'"
      ];
    };
    systemd.services.fan-curve = {
      description = "Apply the thinkfan curve for the current resolved fan mode";
      wantedBy = ["multi-user.target"];
      after = ["ryzen-smu-bridge.service"];
      requires = ["ryzen-smu-bridge.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe fanCurveApply;
      };
    };
    systemd.paths.fan-curve = {
      description = "Watch resolved fan mode; swap thinkfan curve on change";
      wantedBy = ["multi-user.target"];
      after = ["ryzen-smu-bridge.service"];
      pathConfig.PathModified = "/run/thinkfan/mode-resolved";
    };
    networking.hostName = "thanatos";
    nix.gc = {
      automatic = true;
      options = "--delete-older-than 7d";
      dates = "daily";
    };
    hardware = {
      amdgpu = {
        opencl.enable = true;
        overdrive.enable = true;
        initrd.enable = true;
      };
      graphics = {
        enable = true;
        enable32Bit = true;
        # driSupport = true;
        # driSupport32Bit = true;

        extraPackages = with pkgs; [
          # vaapiVdpau
          # libvdpau-va-gl
        ];
      };
    };

    # Point the whole system at the patched xkb dir (cadetXkbDir, defined in the
    # let block above) and enable the cadet:parens option. The layout stays plain
    # `us`; the option adds the FK13-16 -> unshifted paren/brace mapping on top,
    # merged after inet(evdev) so it actually wins. xkb.dir feeds ckbcomp (TTY
    # console) and XKB_CONFIG_ROOT feeds Hyprland's libxkbcommon (both must point
    # at the patched dir or the option is "unrecognized"). NOTE: XKB_CONFIG_ROOT
    # is a session variable -- a running session must re-login to pick it up.
    services.xserver.xkb.dir = "${cadetXkbDir}/share/X11/xkb";
    environment.sessionVariables.XKB_CONFIG_ROOT = "${cadetXkbDir}/share/X11/xkb";
    services.xserver.xkb.layout = "us";
    services.xserver.xkb.options = "cadet:parens";
    console.useXkbConfig = true;

    services.kanata = {
      enable = true;
      keyboards.laptop = {
        devices = ["/dev/input/by-path/platform-i8042-serio-0-event-kbd"];
        # = kmonad fallthrough = true. The module wraps this in (defcfg ...)
        # and appends linux-dev + linux-continue-if-no-devs-found itself, so
        # `config` below is defsrc/deflayer/defalias ONLY (no defcfg).
        extraDefCfg = "process-unmapped-keys yes";
        # Full keyboard map: unchanged keys map to themselves so you can read
        # off what is/isn't remapped. Remaps: esc->caps, caps->@cen (tap=esc/
        # hold=ctrl), lctl->esc, lsft/rsft->cadet, lmet<->lalt swap. Cadet:
        # tap=(/) , double-tap={/} (f13-16 -> paren/brace via the cadet:parens
        # XKB option), hold=Shift.
        config = ''
          (defsrc
            esc  f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12  prnt ins del
            grv  1 2 3 4 5 6 7 8 9 0 - =  bspc
            tab  q w e r t y u i o p [ ] \
            caps a s d f g h j k l ; ' ret
            lsft z x c v b n m , . / rsft up
            lctl lmet lalt           spc            ralt rctl left down rght
          )
          (deflayer base
            caps  f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12  prnt ins del
            grv  1 2 3 4 5 6 7 8 9 0 - =  bspc
            tab  q w e r t y u i o p [ ] \
            @cen a s d f g h j k l ; ' ret
            @lcdt z x c v b n m , . / @rcdt up
            esc  lalt lmet           spc            ralt rctl left down rght
          )
          (defalias
            cen  (tap-hold 200 200 esc lctl)
            lcdt (tap-hold-release 200 200 (tap-dance ${toString cadetDoubleTapMs} (f13 f15)) lsft)
            rcdt (tap-hold-release 200 200 (tap-dance ${toString cadetDoubleTapMs} (f14 f16)) rsft)
          )
        '';
      };
      keyboards.razer = {
        # Both interfaces of the same board (mirrors the two kmonad blocks).
        # If the Razer double-types, drop the first (event-kbd) path and keep
        # if01-event-kbd (the one the kmonad comments preferred).
        devices = [
          "/dev/input/by-id/usb-Razer_Razer_BlackWidow_Tournament_Edition_Chroma-event-kbd"
          "/dev/input/by-id/usb-Razer_Razer_BlackWidow_Tournament_Edition_Chroma-if01-event-kbd"
        ];
        extraDefCfg = "process-unmapped-keys yes";
        # Same remaps as laptop EXCEPT: no lmet/lalt swap, and cen also does
        # double-tap = esc + ':' (neovim command mode). S-; = ':'.
        config = ''
          (defsrc
            esc       f1 f2 f3 f4  f5 f6 f7 f8  f9 f10 f11 f12   sys  slck pause
            grv  1 2 3 4 5 6 7 8 9 0 - =  bspc                   ins  home pgup
            tab  q w e r t y u i o p [ ] \                        del  end  pgdn
            caps a s d f g h j k l ; ' ret
            lsft z x c v b n m , . / rsft                              up
            lctl lmet lalt          spc            ralt cmp rctl       left down rght
          )
          (deflayer base
            caps      f1 f2 f3 f4  f5 f6 f7 f8  f9 f10 f11 f12   sys  slck pause
            grv  1 2 3 4 5 6 7 8 9 0 - =  bspc                   ins  home pgup
            tab  q w e r t y u i o p [ ] \                        del  end  pgdn
            @cenr a s d f g h j k l ; ' ret
            @lcdt z x c v b n m , . / @rcdt                           up
            esc  lmet lalt          spc            ralt cmp rctl       left down rght
          )
          (defalias
            cenr (tap-hold 200 200 (tap-dance 200 (esc (macro esc S-;))) lctl)
            lcdt (tap-hold-release 200 200 (tap-dance ${toString cadetDoubleTapMs} (f13 f15)) lsft)
            rcdt (tap-hold-release 200 200 (tap-dance ${toString cadetDoubleTapMs} (f14 f16)) rsft)
          )
        '';
      };
      # Failsafe passthrough keyboard. Empty defsrc/deflayer + process-unmapped-
      # keys => every key passes through 1:1 (a plain US keyboard, NO remaps),
      # so this config can never itself fail to load (verified: kanata --check).
      # It grabs the SAME internal keyboard as `laptop`, so it must NOT run
      # concurrently -- the systemd override below sets wantedBy=[] so it never
      # autostarts, and kanata-laptop's OnFailure= starts it only when the main
      # daemon gives up (persistent crash / invalid config). Conflicts= on the
      # laptop unit stops it again when a fixed main daemon comes back. This is
      # the recovery keyboard when the LIBINPUT_IGNORE rule below would otherwise
      # leave you with a dead keyboard inside the Wayland session.
      keyboards.fallback = {
        devices = ["/dev/input/by-path/platform-i8042-serio-0-event-kbd"];
        extraDefCfg = "process-unmapped-keys yes";
        config = ''
          (defsrc)
          (deflayer base)
        '';
      };
    };
    # Give the kanata daemons realtime scheduling + Restart=always (see
    # kanataRtSched above). The upstream module hardcodes the units, so patch
    # serviceConfig here. Gated on services.kanata.enable so that disabling
    # kanata does not synthesize half-defined units with no ExecStart.
    systemd.services."kanata-laptop" = lib.mkIf config.services.kanata.enable {
      serviceConfig = kanataRtSched;
      # When the main daemon gives up (start-limit exhausted after a persistent
      # crash / invalid config), hand the keyboard to the passthrough failsafe.
      # OnFailure only fires on the "failed" state, which Restart=always reaches
      # solely via the start-limit -- so transient crashes still self-heal and
      # only a real, repeating failure triggers the fallback.
      unitConfig.OnFailure = "kanata-fallback.service";
      # Reclaim the device when a fixed main daemon returns: starting this stops
      # the fallback (Conflicts), and After= makes us wait for its grab to be
      # released before we grab.
      conflicts = ["kanata-fallback.service"];
      after = ["kanata-fallback.service"];
    };
    systemd.services."kanata-razer" =
      lib.mkIf config.services.kanata.enable {serviceConfig = kanataRtSched;};
    # The failsafe unit exists (generated from keyboards.fallback) but must
    # never autostart -- it grabs the same device as kanata-laptop. Only
    # kanata-laptop's OnFailure= starts it.
    systemd.services."kanata-fallback" = lib.mkIf config.services.kanata.enable {
      wantedBy = lib.mkForce [];
      serviceConfig = kanataRtSched;
    };

    # Hide the raw internal (i8042) keyboard from libinput/Hyprland. kanata
    # grabs it via EVIOCGRAB and re-emits through its own uinput device, but the
    # compositor still enumerates the physical device and keeps a PER-DEVICE xkb
    # lock state for it. During the brief ungrab window on every kanata restart
    # (each nixos-rebuild activation stops/starts the unit), Hyprland reads the
    # raw keyboard and can latch Caps Lock on that device; kanata then re-grabs,
    # freezing a stale caps=on state that desyncs from the hardware LED and gets
    # re-applied to every window on focus change -- the reproducible "switching
    # window focus turns on Caps Lock" bug. Ignoring the device makes kanata's
    # uinput output the only keyboard the session tracks, so there is nothing to
    # latch or leak. kanata reads evdev directly and is unaffected; the kernel VT
    # also bypasses libinput, so a text-console keyboard still works if kanata is
    # down. Tradeoff: the physical Caps Lock LED no longer lights (Hyprland only
    # drives LEDs on devices it manages); the Esc->caps remap itself still works.
    #
    # CRITICAL: gate this on services.kanata.enable. Without kanata delivering
    # remapped events, an ignored internal keyboard is dead INSIDE the Wayland
    # session; tying the rule to kanata being enabled means `enable = false`
    # automatically restores the plain keyboard. (An external USB keyboard has a
    # different ID_PATH, is never ignored, and is always a recovery path.)
    services.udev.extraRules = lib.mkIf config.services.kanata.enable ''
      ACTION=="add|change", SUBSYSTEM=="input", ENV{ID_PATH}=="platform-i8042-serio-0", ENV{ID_INPUT_KEYBOARD}=="1", ENV{LIBINPUT_IGNORE_DEVICE}="1"
    '';

    # Build-time validation of every kanata config. runCommand runs `kanata
    # --check` on the same body the module will run (wrapped in a minimal defcfg;
    # the module-generated linux-dev lines are boilerplate and are not needed to
    # validate the layers/aliases, which is where hand-edited errors live). A
    # parse/validation error fails the derivation and therefore the whole
    # `nixos-rebuild`, so a broken config never deploys and the running (good)
    # generation stays active. This is the UPSTREAM guard; the passthrough
    # failsafe (keyboards.fallback + OnFailure) is the RUNTIME net for whatever
    # still slips through -- e.g. a config that validates but crashes at runtime.
    # Reads the config strings straight from the evaluated options, so it covers
    # laptop, razer, fallback, and any keyboard added later.
    system.extraDependencies =
      lib.optionals config.services.kanata.enable
      (lib.mapAttrsToList
        (name: kb:
          pkgs.runCommand "kanata-check-${name}" {
            nativeBuildInputs = [config.services.kanata.package];
          } ''
            kanata --check --cfg ${pkgs.writeText "kanata-${name}-check.kdb" ''
              (defcfg ${kb.extraDefCfg})
              ${kb.config}
            ''} && touch "$out"
          '')
        config.services.kanata.keyboards);

    services.fwupd.extraRemotes = ["lvfs-testing"];
    services.fprintd.enable = true;
    services.thinkfan = {
      enable = true;
      smartSupport = true;
      sensors = [
        {
          type = "hwmon";
          query = "/run/thinkfan/temp";
        }
      ];
      fans = [
        {
          type = "tpacpi";
          query = "/proc/acpi/ibm/fan";
        }
      ];
      # smoothed cpu_thm feeds this now, so the spike-bias can relax; -s2 keeps
      # the poll short enough that the safety FORCE_MAX value acts within ~2s.
      extraArgs = ["-b0" "-s2"];
      # Curve is on the cpu_thm scale (~13C below the old EC/Tctl scale).
      # ~6C hysteresis in the working range; the top disengage step is a
      # deliberate tight 2C safety band. Quiet profile is the same curve minus
      # the bridge's QUIET_OFFSET.
      # This block feeds only the module's generated (unused) config -- the
      # live curve comes from the mkForce'd THINKFAN_ARGS + active.yaml below.
      levels = quietLevels;
    };
    services.pixiecore = {
      enable = true;
      openFirewall = true;
      dhcpNoBind = true;
      debug = true;
      # kernel = "https://boot.netboot.xyz";
      kernel = "https://boot.netboot.xyz/ipxe/netboot.xyz.lkrn";
      extraArguments = [
        # "--ipxe-ipxe"
        # "${pkgs.ipxe}/ipxe.efi"
        "--ipxe-efi64"
        "${../../assets/ipxe.efi}"
        # "${../../assets/netboot.xyz.efi}"
        # "--listen-addr"
        # "192.168.200.1"
        "--port"
        "8080"
      ];
    };
    services.udev.packages = let
      slowBoi = let
        # wattage = toString 10000;
        wattage = toString 7000;
        temp = toString 80;
        time = toString 5;
      in
        pkgs.writeShellScriptBin "slowBoi.sh" ''
          # wait for tlp to get settings in
          sleep 3
          # don't mind if boost is disabled on battery
          # ${lib.getExe pkgs.ryzenadj} --stapm-limit ${wattage} --fast-limit ${wattage} --slow-limit ${wattage} \
          #   --apu-slow-limit ${wattage} --slow-time 5 --tctl-temp 95 --apu-skin-temp 65
          ${lib.getExe pkgs.ryzenadj} --stapm-limit ${wattage} --fast-limit ${wattage} --slow-limit ${wattage} \
            --apu-slow-limit ${wattage} --slow-time ${time} --tctl-temp ${temp}
        '';
      fastAfBoi = let
        wattage = toString 45000;
        temp = toString 80;
        time = toString 5;
      in
        pkgs.writeShellScriptBin "fastAfBoi.sh" ''
          # wait for tlp to get settings in
          sleep 3
          while true; do
            # BOOST = $(cat /sys/devices/cpu/cpufreq/boost)
            AC=$(cat /sys/class/power_supply/AC/online)
            if [[ $AC -eq 0 ]];  then
              echo "KILLING BOOST"
              break
            fi
            echo 1 > /sys/devices/system/cpu/cpufreq/boost
            ${lib.getExe pkgs.ryzenadj} --stapm-limit ${wattage} --fast-limit ${wattage} --slow-limit ${wattage} \
              --apu-slow-limit ${wattage} --slow-time ${time} --tctl-temp ${temp}
            # ${lib.getExe pkgs.ryzenadj} --stapm-limit ${wattage} --fast-limit ${wattage} --slow-limit ${wattage} \
            #   --apu-slow-limit ${wattage} --slow-time 5 --tctl-temp 95 --apu-skin-temp 65
            sleep 10
          done
        '';
    in [
      # (pkgs.writeTextFile {
      #   name = "ryzen_laptop";
      #   text = ''
      #     SUBSYSTEM=="power_supply", ATTR{online}=="0", RUN+="${lib.getExe slowBoi}"
      #     SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="${lib.getExe fastAfBoi}"
      #   '';
      #   destination = "/etc/udev/rules.d/99-ryzen_laptop.rules";
      # })
    ];
  };
}
