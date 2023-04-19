# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)

{ inputs, lib, config, pkgs, ... }: {
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules from other flakes (such as nixos-hardware):
    # inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-ssd
    # You can also split up your configuration and import pieces of it here:
    # ./users.nix
    inputs.hardware.nixosModules.dell-xps-15-9560-intel

    inputs.hyprland.nixosModules.default
    {
      programs.hyprland = {
        enable = true;
        xwayland = {
          enable = true;
          hidpi = true;
        };
      };
    }

    inputs.kmonad-pkgs.nixosModules.default
    # Import your generated (nixos-generate-config) hardware configuration
    ./hardware-configuration.nix
    ./tlp.nix
    ../features/kernel
    ../features/auth
  ];
  boot.initrd.availableKernelModules = [
    # fast decrypt for luks
    "aesni_intel"
    "cryptd"
  ];
  # make sure to compile broadcom kernel modules, needed for the bcm4360
  boot.kernelModules = [ "wl" ];
  boot.extraModulePackages = with config.boot.kernelPackages; [
    broadcom_sta
    # to control brightness on non-internal monitors
    ddcci-driver
    # enable temp monitoring subsystem
    tmon
    # enable zfs
    # zfs
    # usb over ip
    # usbip
    # processor stats
    turbostat
  ];
  boot.blacklistedKernelModules = [ "b43" "bcma" ];

  boot.loader = {
    systemd-boot = {
      enable = true;
      memtest86.enable = true;
    };
    efi.canTouchEfiVariables = false;
  };

  boot.kernelParams = [
    # from: https://wiki.archlinux.org/title/Dell_XPS_15_(9560)#Enable_power_saving_features_for_the_i915_kernel_module
    # might remove the rc6 option later.
    "i915.enable_psr=1"
    "i915.enable_rc6=7"
    "i915.enable_fbc=1"
    "i915.disable_power_well=0"
    # Make sure the laptop exposes correct acpi. Makes the laptop less crash prone
    "acpi_rev_override=1"
    # USB-C fix, do not sleep the pcie links
    "pcie_aspm=off"
    # Do not let nouveau take control of the nvidia gpu
    "nouveau.modeset=0"
    # Test option, to see if there is any discernible difference
    "workqueue.power_efficient=1"
    # Self explanatory
    "mitigations=off"
  ];
  kernel-mod.ntfs3.enable = true;
  nixpkgs = {
    overlays = [
      # overlay skeleton
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
      (final: prev: {
        nix = pkgs.unstable.nix;
        cacerts = pkgs.unstable.cacerts;
      })
    ];
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
      nix = {
        binaryCachePublicKeys =
          [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
        binaryCaches = [ "https://cache.nixos.org" ];
      };
    };
  };
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}")
      config.nix.registry;

    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Deduplicate and optimize nix store
      auto-optimise-store = true;
    };
  };

  networking = {
    wireless = {
      iwd = {
        enable = true;
        settings = {
          General = { EnableNetworkConfiguration = true; };
          Settings = {
            AutoConnect = true;
            AlwaysRandomizeAddress = false;
            Hidden = false;
          };
        };
      };
    };
    hostName = "nyx";
    networkmanager = {
      enable = true;
      wifi.powersave = true;
      enableFccUnlock = true;
      wifi.backend = "iwd";
    };
    nameservers = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
    firewall.enable = true;
  };

  systemd.network.links = {
    "80-iwd" = lib.mkForce {
      enable = true;
      matchConfig = { Type = "wlan"; };
      linkConfig = { NamePolicy = "mac"; };
    };
  };

  time.timeZone = "America/Los_Angeles";

  users.users = {
    michael = {
      hashedPassword =
        "$6$WXBvFlgvwtcGIdYg$IS.Rii0vfzj2j5nDqpPm.a0maMqRYTQ2u/kaRaaO2Css/rzsSYghXPhlVOFAUTma1UU19oSCvccLfe1LRMF8T/";
      isNormalUser = true;
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [ ];
      extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    };
  };

  services.openssh = {
    enable = true;
    permitRootLogin = "no";
    passwordAuthentication = false;
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    audio.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    systemWide = false;
    wireplumber.enable = true;
  };

  services.zerotierone = {
    enable = true;
    joinNetworks = [ "565799d8f65ab6a3" ];
  };

  services.onedrive = {
    enable = true;
    package = pkgs.unstable.onedrive;
  };

  services.udev = {
    extraRules = ''
      # Remove NVIDIA USB xHCI Host Controller devices, if present
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
      # Remove NVIDIA USB Type-C UCSI devices, if present
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
      # Remove NVIDIA Audio devices, if present
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
      # Remove NVIDIA VGA/3D controller devices
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
    '';
  };

  services.kmonad = {
    enable = true;
    keyboards = {
      laptop-internal = {
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
                              (defalias
                                


                    	  )
                              (deflayer qwerty ;; Default layer, just switched caps for esc, lctl for caps, and esc for lctl 
                                caps   f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12  prnt  ins  del
                                `     1    2    3    4    5    6    7    8    9    0    -    =    bspc
                                tab   q    w    e    r    t    y    u    i    o    p    [    ]    \
                                @cen  a    s    d    f    g    h    j    k    l    ;    '    ret
                                lsft  z    x    c    v    b    n    m    ,    .    /    rsft up
                                esc  lmet lalt           spc            ralt rctl left down right
                              )
          (defalias
            cen (multi-tap 180 lctl esc)
            ;;cen (multi-tap 200 a 200 b 200 c d)
          )
        '';

      };
      rzr-blkwd-te = {
        # Was not able to debug why i need to use if01 instead of the actual event kdb, this means
        # that ripple effects wont work.
        device =
          "/dev/input/by-id/usb-Razer_Razer_BlackWidow_Tournament_Edition_Chroma-event-kbd";
        defcfg = {
          enable = true;
          fallthrough = true;
        };
        # This is to deal with openrazer taking over the keyboard.
        extraGroups = [ "openrazer" ];
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
            lsft z    x    c    v    b    n    m    ,    .    /    rsft                    up       
            esc  lmet lalt           spc            ralt      cmp  rctl              left down rght
          )


          (defalias
            cen (multi-tap 170 lctl esc)
            ;;cen (multi-tap 200 a 200 b 200 c d)
          )

        '';

      };
    };
  };

  hardware.openrazer = {
    enable = true;
    devicesOffOnScreensaver = true;
    keyStatistics = true;
    users = [ "michael" ];
  };

  hardware.bluetooth = {
    enable = true;
    settings = { General = { Enable = "Source,Sink,Media,Socket"; }; };
    package = pkgs.bluezFull;
  };

  services.blueman.enable = true;

  environment.etc."wireplumber/bluetooth.lua.d/51-bluez-config.lua".text = ''
    bluez_monitor.properties = {
    	["bluez5.enable-sbc-xq"] = true,
    	["bluez5.enable-msbc"] = true,
    	["bluez5.enable-hw-volume"] = true,
    	["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
    }
  '';

  environment.systemPackages = with pkgs; [
    mosh
    wget
    curl
    nerdfonts
    gcc_multi
    openssl

  ];

  yubiAuth.enable = true;

  environment.pathsToLink = [ "/share/zsh" ];

  fonts = {
    fonts = with pkgs; [ noto-fonts noto-fonts-emoji nerdfonts powerline ];
    enableDefaultFonts = true;

    fontconfig.defaultFonts.monospace =
      lib.mkForce [ "Source Code Pro for Powerline" ];
  };

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.dnsname.enable = true;
    };
    libvirtd = { enable = true; };
    kvmgt = { enable = true; };
  };
  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "21.11";
}
