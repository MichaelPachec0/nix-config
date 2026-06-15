{
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./tlp.nix
  ];
  config = {
    nixpkgs.overlays = [
      # TODO: make sure to change this!
      (self: _super: {
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
    ];
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
        # {
        #   type = "tpacpi";
        #   query = "/proc/acpi/ibm/thermal";
        #   indices = [0];
        # }
        {
          type = "hwmon";
          query = "/sys/devices/platform/thinkpad_hwmon/hwmon/hwmon6/temp1_input";
        }
      ];
      fans = [
        {
          type = "tpacpi";
          query = "/proc/acpi/ibm/fan";
        }
      ];
      # to combat temp spikes
      extraArgs = ["-b-3"];
      levels = [
        # [0 0 45]
        # [1 40 50]
        # [2 45 55]
        # [3 50 60]
        # [4 55 65]
        # [5 60 65]
        # [6 63 66]
        # [7 69 72]
        # [0 0 58]
        # [1 52 62]
        # [2 55 65]
        # [3 58 68]
        # [5 61 72]
        # [7 66 85]
        [0 0 58] # Fan off below 58°C
        [1 54 62] # Low fan from 58-62°C
        [2 57 66] # Moderate fan if climbing
        [3 60 70] # Start reacting to higher sustained temps
        [5 65 82] # High fan only if 80+ persists
        [7 75 88] # Max fan near thermal throttle
        ["level disengaged" 87 32767]
        # [
        #   0
        #   0
        #   55
        # ]
        # [
        #   1
        #   40
        #   60
        # ]
        # [
        #   2
        #   50
        #   61
        # ]
        # [
        #   3
        #   52
        #   63
        # ]
        # [
        #   6
        #   56
        #   65
        # ]
        # [
        #   7
        #   60
        #   85
        # ]
        # [
        #   "level disengaged"
        #   80
        #   32767
        # ]
        # [0 0 45]
        # [1 40 50]
        # [2 45 55]
        # [3 50 60]
        # [4 55 65]
        # [5 60 68]
        # [6 63 70]
        # [7 66 73]
        # ["level disengaged" 69 78]
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
    services.udev.packages = [
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
