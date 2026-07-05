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
      case "$mode" in
        perf|quiet) printf '%s\n' "$mode" > /run/thinkfan/mode ;;
        auto)       rm -f /run/thinkfan/mode ;;
        *) echo "usage: fan-mode perf|quiet|auto" >&2; exit 2 ;;
      esac
      echo "fan-mode: ''${mode} (clears on AC state change)"
    '';
  };
in {
  imports = [
    ./tlp.nix
  ];
  config = {
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

    services.kmonad = {
      enable = true;
      keyboards = {
        laptop-internal = {
          # TODO: change path
          device = "/dev/input/by-path/platform-i8042-serio-0-event-kbd";
          defcfg = {
            enable = true;
            fallthrough = true;
          };
          config = ''
            (defsrc ;; Default keymap for laptop
              esc   f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12  prnt  ins  del
              `     1    2    3    4    5    6    7    8    9    0    -    =    bspc
              tab   q    w    e    r    t    y    u    i    o    p    [    ]    \
              caps  a    s    d    f    g    h    j    k    l    ;    '    ret
              lsft  z    x    c    v    b    n    m    ,    .    /    rsft up
              lctl  lmet lalt           spc            ralt rctl left down right
            )
            (deflayer qwerty ;; Default layer, just switched caps for esc, lctl for caps, and esc for lctl
              caps   f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12  prnt  ins  del
              `     1    2    3    4    5    6    7    8    9    0    -    =    bspc
              tab   q    w    e    r    t    y    u    i    o    p    [    ]    \
              @cen  a    s    d    f    g    h    j    k    l    ;    '    ret
              @lcdt z    x    c    v    b    n    m    ,    .    /    @rcdt up
              esc  lalt lmet           spc            ralt rctl left down right
            )
            (defalias
              ;; cen (tap-next esc lctl)
              ;; tap = esc
              ;; double tap = esc + : (for neovim to enter command mode)
              ;; held + key = ctrl + key
              ;; held > 200ms = ctrl
              ;; cen (tap-hold-next 200 (tap-next esc (tap-macro-release esc : :delay 2)) lctl)
              cen (tap-next esc lctl)
              ;; hel
              ;; simple cadet keys, would like in the future to be able make this a tap dance
              ;; more expansive cadet keys, when tapped once its a ( or ), double tapped { or } held shift, held for 200ms and then released shift.
              lcdt (tap-next  \(  lsft )
              rcdt (tap-next  \)  rsft )
              acrtl ( tap-next a lctl )
              smet ( tap-next s lmet )
              dalt ( tap-next d lalt )
              fshift (tap-next f lsft )

              jshift (tap-next f rsft )
              ;; kalt (tap-next )
              ;; lcdt (tap-hold-next 200 (tap-next \( { ) lsft )
              ;; rcdt (tap-hold-next 200 (tap-next \) } ) rsft )

            )
          '';
        };
        rzr-blkwd-te-bad = {
          # WARN: Was not able to debug why i need to use if01 instead of the actual event kdb, this means
          # that ripple effects wont work.
          # NOTE: even with extraGroups, for some reason this does not work reliably. This is probably explained by
          # openrazer sometimes not working in some cases.
          # TODO: (low prio) Investigate the problem, or workaround by disabling openrazer.
          device = "/dev/input/by-id/usb-Razer_Razer_BlackWidow_Tournament_Edition_Chroma-event-kbd";
          #"/dev/input/by-id/usb-Razer_Razer_BlackWidow_Tournament_Edition_Chroma-if01-event-kbd";
          defcfg = {
            enable = true;
            fallthrough = true;
          };
          # This is to deal with openrazer taking over the keyboard.
          extraGroups = ["openrazer"];
          config = ''
            (defsrc ;; the sys is also a prnt scr key
              esc       f1   f2   f3   f4    f5   f6   f7   f8   f9   f10  f11  f12    sys  slck pause
              grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc    ins  home pgup
              tab  q    w    e    r    t    y    u    i    o    p    [    ]    \       del  end  pgdn
              caps a    s    d    f    g    h    j    k    l    ;    '    ret
              lsft z    x    c    v    b    n    m    ,    .    /    rsft                    up
              lctl lmet lalt           spc            ralt      cmp  rctl              left down rght
            )

            (deflayer qwerty ;; the sys is also a prnt scr key
              caps      f1   f2   f3   f4    f5   f6   f7   f8   f9   f10  f11  f12    sys  slck pause
              grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc    ins  home pgup
              tab  q    w    e    r    t    y    u    i    o    p    [    ]    \       del  end  pgdn
              @cen a    s    d    f    g    h    j    k    l    ;    '    ret
              @lcdt z    x    c    v    b    n    m    ,    .    /   @rcdt                    up
              esc  lmet lalt           spc            ralt      cmp  rctl              left down rght
            )
            ;; (double_tap_hold single_tap )

            (defalias
              ;; cen (tap-next esc lctl)
              ;; tap = esc
              ;; double tap = esc + : (for neovim to enter command mode)
              ;; held + key = ctrl + key
              ;; held > 200ms = ctrl
              cen (tap-hold-next 200 (tap-next esc (tap-macro esc :)) lctl)
              ;;cen (multi-tap 170 lctl esc)
              ;;cen (multi-tap 200 a 200 b 200 c d)
              ;; hel
              ;; simple cadet keys, would like in the future to be able make this a tap dance
              ;; more expansive cadet keys, when tapped once its a ( or ), double tapped { or } held shift, held for 200ms and then released shift.
              lcdt (tap-hold-next 200 (tap-next \( { ) lsft )
              rcdt (tap-hold-next 200 (tap-next \) } ) rsft )

            )
          '';
        };
        rzr-blkwd-te = {
          # NOTE: See the previous comments rzr-blkwd entry.
          device =
            #"/dev/input/by-id/usb-Razer_Razer_BlackWidow_Tournament_Edition_Chroma-event-kbd";
            "/dev/input/by-id/usb-Razer_Razer_BlackWidow_Tournament_Edition_Chroma-if01-event-kbd";
          defcfg = {
            enable = true;
            fallthrough = true;
          };
          # This is to deal with openrazer taking over the keyboard.
          extraGroups = ["openrazer"];
          config = ''
            (defsrc ;; the sys is also a prnt scr key
              esc       f1   f2   f3   f4    f5   f6   f7   f8   f9   f10  f11  f12    sys  slck pause
              grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc    ins  home pgup
              tab  q    w    e    r    t    y    u    i    o    p    [    ]    \       del  end  pgdn
              caps a    s    d    f    g    h    j    k    l    ;    '    ret
              lsft z    x    c    v    b    n    m    ,    .    /    rsft                    up
              lctl lmet lalt           spc            ralt      cmp  rctl              left down rght
            )
            (deflayer qwerty ;; the sys is also a prnt scr key
              caps      f1   f2   f3   f4    f5   f6   f7   f8   f9   f10  f11  f12    sys  slck pause
              grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc    ins  home pgup
              tab  q    w    e    r    t    y    u    i    o    p    [    ]    \       del  end  pgdn
              @cen a    s    d    f    g    h    j    k    l    ;    '    ret
              @lcdt z    x    c    v    b    n    m    ,    .    /   @rcdt                    up
              esc  lmet lalt           spc            ralt      cmp  rctl              left down rght
            )
            (defalias
              ;; cen (tap-next esc lctl)
              ;; tap = esc
              ;; double tap = esc + : (for neovim to enter command mode)
              ;; held + key = ctrl + key
              ;; held > 200ms = ctrl
              cen (tap-hold-next 200 (tap-next esc (tap-macro esc :)) lctl)
              ;;cen (multi-tap 170 lctl esc)
              ;;cen (multi-tap 200 a 200 b 200 c d)
              ;; hel
              ;; simple cadet keys, would like in the future to be able make this a tap dance
              ;; more expansive cadet keys, when tapped once its a ( or ), double tapped { or } held shift, held for 200ms and then released shift.
              lcdt (tap-hold-next 200 (tap-next \( { ) lsft )
              rcdt (tap-hold-next 200 (tap-next \) } ) rsft )

            )
          '';
        };
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
      # Curve is on the cpu_thm scale (~13C below the old EC/Tctl scale). Wide
      # ~6-7C hysteresis so it parks instead of hunting. Quiet profile is the
      # same curve minus the bridge's QUIET_OFFSET.
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
