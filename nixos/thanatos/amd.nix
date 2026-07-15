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
    };
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
      levels = [
        [0 0 55]
        [2 48 66]
        [4 60 76]
        [5 70 84]
        [7 78 90]
        ["level disengaged" 88 32767]
      ];
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
