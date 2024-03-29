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
    inputs.hardware.nixosModules.common-pc-laptop-ssd

    #inputs.nwg-displays-pkgs.packages.${pkgs.system}.nwg-displays

    inputs.kmonad-pkgs.nixosModules.default
    # Import your generated (nixos-generate-config) hardware configuration
    ./hardware-configuration.nix
    ./tlp.nix
    ../../features/nixos/kernel
    ../../features/nixos/auth
    ../../features/nixos/logitech
    ../../features/nixos/login
    ../../features/nixos/desktop
    ../../features/nixos/common
  ];
  boot.initrd.availableKernelModules = [
    # fast decrypt for luks
    "aesni_intel"
    "cryptd"
  ];
  # make sure to compile broadcom kernel modules, needed for the bcm4360
  boot.kernelModules = [ "wl" ];
  boot.extraModulePackages = with config.boot.kernelPackages;
    [
      broadcom_sta
      # to control brightness on non-internal monitors
      # ddcci-driver
      #  enable zfs (still broken in 6.2.x)
      # zfs
    ];
  boot.blacklistedKernelModules = [ "b43" "bcma" ];

  boot.loader = {
    systemd-boot = {
      enable = true;
      memtest86.enable = true;
      consoleMode = "auto";
    };
    efi.canTouchEfiVariables = false;
  };
  services.fwupd.enable = true;
  boot.kernelParams = [
    # from: https://wiki.archlinux.org/title/Dell_XPS_15_(9560)#Enable_power_saving_features_for_the_i915_kernel_module
    #"i915.enable_psr=1"
    #"i915.enable_fbc=1"
    #"i915.disable_power_well=0"
    # Make sure the laptop exposes correct acpi. Makes the laptop less crash prone
    "acpi_rev_override=1"
    # let tlp handle this part
    "pcie_aspm=off"
    # USB-C fix, do not sleep the pcie links
    #"pcie_aspm=off"
    # "pcie_port_pm=off"
    # Do not let nouveau take control of the nvidia gpu
    "nouveau.modeset=0"
    # Test option, to see if there is any discernible difference
    #"workqueue.power_efficient=1"
    # Self explanatory
    "mitigations=off"
  ];

  boot.kernelPackages = pkgs.linuxPackages_6_1;
  # taken from disable nvidia
  boot.extraModprobeConfig = ''
    blacklist nouveau
    options nouveau modeset=0

  '';

  # Make sure swap gets unlocked.
  boot.initrd.luks.devices."swap".device =
    "/dev/disk/by-uuid/c20f4b7d-5f67-4f24-b796-c6d1446ecd26";

  kernel.mod.ntfs3.enable = true;
  console = {
    font = "${pkgs.terminus_font}/share/consolefonts/ter-v32n.psf.gz";
    earlySetup = true;
  };
  audio.enable = true;
  devMachine.enable = true;
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
        binaryCachePublicKeys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="

        ];
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
    firewall = {
      enable = true;
      allowedTCPPortRanges = [
        # kdeconnect
        {
          from = 1714;
          to = 1764;
        }
        # spotify p2p
        {
          from = 57621;
          to = 57621;
        }
      ];
      allowedUDPPortRanges = [
        # kdeconnect
        {
          from = 1714;
          to = 1764;
        }
      ];
    };
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
  # recomended keyring to use.
  services.gnome.gnome-keyring.enable = true;
  # Needed for sway/hyprland usage HM as per: https://nixos.wiki/wiki/Sway#Using_Home_Manager
  security.polkit.enable = true;

  services.openssh = {
    enable = true;
    permitRootLogin = "no";
    passwordAuthentication = false;
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
    packages = let
      command = "${pkgs.systemd}/bin/loginctl";
      check = pkgs.writeShellScriptBin "yubicheck.sh" ''
        #!${pkgs.stdenv.shell}
        sleep 1
        check=$(${
          lib.getExe pkgs.yubikey-manager
        } list | ${pkgs.busybox}/bin/wc -l)
        if [[ $check -lt 1 ]]; then
          ${command} lock-sessions --no-ask-password
        fi
      '';
      # Reminder to test unlock with sleep timer so that all the screens are init'ed before the
      # screenlock is killed.
      # NOTE: will probably use this but with a check if swaylock is already running
      # ps aux | grep swaylock | wc -l 
      #   is going to be >=2 when swaylock is not running else it is running
      #      commandPkg = pkgs.writeShellScript "yubikey-lock.sh" ''
      #        if [ -z "$(lsusb | grep Yubikey)" ] ; then
      #          ${command} lock-sessions --no-ask-password
      #        fi
      #      '';
    in [
      (pkgs.writeTextFile {
        name = "yubikey-lock";
        text = ''
          SUBSYSTEM=="usb", ENV{PRODUCT}=="1050/407/543", ACTION=="remove", RUN+="${
            lib.getExe check
          }"
        '';
        destination = "/etc/udev/rules.d/5-yubikey-lock.rules";
      })
    ];
    extraRules = ''
      # Remove NVIDIA USB xHCI Host Controller devices, if present
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
      # Remove NVIDIA USB Type-C UCSI devices, if present
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
      # Remove NVIDIA Audio devices, if present
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
      # Remove NVIDIA VGA/3D controller devices
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
      # Disable fingerprint reader
      SUBSYSTEM=="usb", ATTRS{idVendor}=="27c6", ATTRS{idProduct}=="5395", ATTR{authorized}="0"
    '';
  };

  services.logid.enable = true;
  services.graphicalLogin.enable = true;

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

  services.hardware.bolt.enable = true;

  environment.systemPackages = with pkgs; [
    fwupd
    mosh
    wget
    curl
    nerdfonts
    gcc_multi
    #openssl
    niv
    # intel specific tools
    inteltool
    intel-gpu-tools
    # to format nix files
    nixfmt
    # create docs from nix files
    nixdoc
    # check which pkgs take space
    # i: https://github.com/symphorien/nix-du
    unstable.nix-du
    # dot command needed by nix-du
    graphviz
    # check whats compiling
    nix-top
    # scripts can set dependencies inside themselves
    # i: https://github.com/madjar/nixbang
    nixbang
    # create oci images from repos
    # gh: https://github.com/railwayapp/nixpacks
    # i: https://nixpacks.com/docs/getting-started
    nixpacks
    # dependicies as a tree
    nix-tree
    nix-diff
    # hash calulation for nixpkgs/docker/github
    nix-prefetch-scripts
    rnix-hashes
    nix-prefetch-docker
    nix-prefetch-github
    config.boot.kernelPackages.turbostat
    config.boot.kernelPackages.tmon
  ];

  yubiAuth.enable = true;

  environment.pathsToLink = [ "/share/zsh" ];

  fonts = {
    fonts = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      (nerdfonts.overrideAttrs (prev: { enableWindowsFonts = true; }))
      winePackages.fonts
      vistafonts
      powerline
    ];
    enableDefaultFonts = true;
    fontconfig = {
      subpixel = { lcdfilter = "default"; };
      defaultFonts.monospace = lib.mkForce [ "Source Code Pro for Powerline" ];

    };
  };
  desktop = {
    common.enable = true;
    wayland.laptop = true;
  };

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork = { settings = { dns_enabled = true; }; };
    };
    libvirtd = { enable = true; };
    kvmgt = { enable = true; };
  };
  # TODO: move this to its own file
  programs.kdeconnect.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "21.11";
}
