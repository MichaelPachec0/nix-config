# This is your system's configuration file.ny
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
} @ args: let
  keys = import ../../helpers/keys.nix;
  yubikey-manager = pkgs.yubikey-manager;
  # NOTE: This is not needed anymore. This is for compat reasons.
  thermald = pkgs.thermald;
in {
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules from other flakes (such as nixos-hardware):
    # inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-ssd
    # You can also split up your configuration and import pieces of it here:
    # ./users.nix

    #inputs.nwg-displays-pkgs.packages.${pkgs.system}.nwg-displays

    # inputs.kmonad-pkgs.nixosModules.default
    inputs.flake-playground.nixosModules.cynthion
    inputs.flake-playground.nixosModules.zsa
    # Import your generated (nixos-generate-config) hardware configuration
    ../../features/nixos/desktop/common/neovim.nix
    ../../features/nixos/auth
    ../../features/nixos/logitech
    ../../features/nixos/login
    ../../features/nixos/desktop
    ../../features/nixos/common
    ../../helpers/caches.nix
    ../../features/nixos/virtualization
    ../../features/nixos/common/deploy.nix
    inputs.nix-gaming.nixosModules.pipewireLowLatency
  ];
  config = {
    boot.initrd.availableKernelModules = [
      # fast decrypt for luks
      "cryptd"
    ];
    boot.initrd.kernelModules = [];
    # make sure to compile broadcom kernel modules, needed for the bcm4360
    boot.kernelModules = ["wl"];
    boot.extraModulePackages =
      (with config.kernel.mod.kernelPkg; [
        # broadcom_sta
        # to control brightness on non-internal monitors
        # WARN: AS of JUL 24 2023 this is failing to compile, disable for now
        # ddcci-driver

        #  enable zfs (still broken in 6.3.x)
        #zfs
        # exfat-nofuse
      ])
      ++ (with pkgs.linuxPackages; []);
    # WARN:: (HIGH PRIO) THIS SHOULD NOT BE NEEDED BUT IT IS, NEED TO INVESTIGATE PRONTO
    # nixpkgs.config.permittedInsecurePackages =  [inputs.easy-tether.packages.${pkgs.system}.default];
    # NOTE: blacklisting b43 and bcma so they do not conflict with the closed source broadcom_sta
    # blacklist tpm for now since sleep errors pop up pertaining to it.
    # TODO: (low prio) (research/debugging) diagnose and find the problem to this.
    # Also since encryption is enabled, tpm gets tied to the trusted kernel module so this needs to be
    # removed here as it slows down sleep, from the look of things it is an exponetial slowdown.
    # ax88179_178a: this kills my ASIX Electronics Corp. AX88179 Gigabit Ethernet adapter
    boot.blacklistedKernelModules = [
      "b43"
      "bcma"
      # "tpm"
      # "psmouse"
      # TODO: 9560 borked changes
      # Disable rtsx driver because the hardware failed a while ago, shaves linux loading time.
      # "rtsx_pci"
      # "sdmmc"
    ];

    boot.kernel.sysctl = {
      # NOTE: more responsive memory options, defaults for some reason gave me issues during sleep after longer use.
      # "vm.vfs_cache_pressure" = 200;
      # "vm.dirty_ratio" = 3;
      # "vm.swappiness" = 15;
      # v2
      # "vm.dirty_ratio" = 50;
      # "vm.dirty_background_ratio" = 20;
      # "vm.swappiness" = 90;
      # "vm.swappiness" = 75;
      # v3
      # "vm.swappiness" = 190;
      # "vm.vfs_cache_pressure" = 50;
      #
      # "vm.dirty_background_ratio" = 10;
      # "vm.dirty_ratio" = 30;

      # NOTE: dont recall what this was for, but this was apart of the memory issues
      # "vm.page-cluster" = 3;

      # v3
      # "vm.page-cluster" = 0;

      # "vm.watermark_scale_factor" = 150;

      # v3
      "fs.inotify.max_user_watches" = 65536;
      # NOTE: zen stuff
      # "kernel.sched_latency_ns" = 4000000;

      # should be one-eighth of sched_latency (this ratio is not
      # configurable, apparently -- so while zen changes that to
      # one-tenth, we cannot):

      # v3
      # "kernel.sched_min_granularity_ns" = 500000;
      # "kernel.sched_wakeup_granularity_ns" = 50000;
      # "kernel.sched_migration_cost_ns" = 250000;
      # "kernel.sched_cfs_bandwidth_slice_us" = 3000;
      # "kernel.sched_nr_migrate" = 128;

      # NOTE: https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 125;
      "vm.page-cluster" = 0;
      "vm.swappiness" = 180;
      # based on the at least 1% free
      # ie 32714204 * 0.01 = 327142.04
      "vm.min_free_kbytes" = 335544;
    };

    services.fwupd.enable = false;
    # taken from disable nvidia
    # boot.extraModprobeConfig = ''
    #   blacklist nouveau
    #   blacklist rivafb
    #   blacklist nvidiafb
    #   blacklist rivatv
    #   blacklist nv
    # '';

    # Make sure swap gets unlocked.
    boot.supportedFilesystems = ["ntfs"];

    # NOTE: This requires a recompile, which takes forever on the laptop, disable for now.

    # NOTE: make sure on console is readable, as device is encrypted.
    console = {
      font = "${pkgs.terminus_font}/share/consolefonts/ter-v32n.psf.gz";
      earlySetup = true;
    };
    audio.enable = true;
    devMachine.enable = true;
    report-changes.enable = true;
    nixpkgs = {
      overlays = [
        # (
        #   final: prev: {
        #     linux-firmware = pkgs.master.linux-firmware;
        #   }
        # )
      ];
      config = {
        allowUnfree = true;
        segger-jlink.acceptLicense = true;
        # inputs.easy-tether.packages.${pkgs.system}.default
        # permittedInsecurePackages = [
        #   "openssl-1.1.1w"
        # ];
      };
    };
    zramSwap = {
      enable = true;
      # memoryPercent = 25;
    };

    nix = {
      # This will add each flake input as a registry
      # To make nix3 commands consistent with your flake
      registry = lib.mapAttrs (_: value: {flake = value;}) inputs;

      # This will additionally add your inputs to the system's legacy channels
      # Making legacy nix commands consistent as well, awesome!
      nixPath =
        lib.mapAttrsToList (key: value: "${key}=${value.to.path}")
        config.nix.registry;

      settings = {
        # Enable flakes and new 'nix' command
        experimental-features = "nix-command flakes";
        # Deduplicate and optimize nix store
        auto-optimise-store = true;
        # TODO: (low prio) remote building.
        trusted-users = ["deploy" "michael"];
      };
    };

    networking = {
      useDHCP = false;
      bridges = {
        br0 = {
          interfaces = [];
        };
      };
      interfaces = {
        # NOTE: enable arp proxy, to allow for wireless bridging
        # ref: https://johnlewis.ie/wireless-bridging-the-third-way/
        # br0 = {
        #   useDHCP = true;
        #   proxyARP = true;
        # };
        #   wlx9cb6d0e1d83b = {
        #     proxyARP = true;
        #     useDHCP = true;
        #   };
      };
      wireless = {
        userControlled = true;
        iwd = {
          enable = false;
          settings = {
            General = {
              EnableNetworkConfiguration = true;
              AddressRandomization = "network";
            };
            Settings = {
              AutoConnect = true;
              # NOTE: bcm4360 driver is not able to function with these options enabled.
              AlwaysRandomizeAddress = false;
              Hidden = false;
            };
          };
        };
      };
      networkmanager = {
        enable = true;
        # getting errors with ax210 with powersave on true
        wifi.powersave = true;
        # wifi.backend = "iwd";
        wifi.backend = "wpa_supplicant";

        plugins = with pkgs; [
          # networkmanager-fortisslvpn
          # networkmanager-iodine
          # networkmanager-l2tp
          networkmanager-openconnect
          networkmanager-openvpn
          # networkmanager-sstp
          networkmanager-strongswan
          # networkmanager-vpnc
        ];
        settings = {
          connectivity = {
            # TODO: change? this is to text connectivity
            uri = "http://static.redhat.com/test/rhel-networkmanager.txt";
            response = "OK";
            interval = 300;
          };
        };
      };

      firewall = {
        enable = true;
        allowedTCPPorts = [
          # rquickshare
          17000
        ];
        allowedTCPPortRanges = [
          # kdeconnect
          {
            from = 1714;
            to = 1764;
          }
          # spotify p2p
          {
            from = 57621;
            to = 57622;
          }
          # charles?
          {
            from = 8888;
            to = 8889;
          }
        ];
        allowedUDPPortRanges = [
          # scream
          {
            from = 4011;
            to = 4011;
          }
          # kdeconnect
          {
            from = 1714;
            to = 1764;
          }
          {
            # test port
            from = 9999;
            to = 9999;
          }
        ];
      };
      nameservers = ["1.1.1.1" "8.8.8.8" "9.9.9.9"];
      hosts = {
        "0.0.0.0" = [
          # spotify_player workaround, see https://github.com/librespot-org/librespot/issues/972#issuecomment-2320943137
          # again ugh, i thought this was fixed, ncspot
          # "apresolve.spotify.com"
        ];
        "127.0.0.1" = [];
        "192.168.0.2" = [];
      };
    };
    systemd.services."zerotierone" = {after = ["dhcpcd.service"];};

    # NOTE: still need to find how I can use this and have captive portal work.

    # TODO: (very low prio) revisit this much later, this is a really nice to have (either DoH or DoT).
    # from a reddit thread:

    # I have a similar setup and the same use case problem: networkd + resolved, DNS-over-HTTPS as much
    # as possible (with dnsproxy), need to access public wifi with hijack-based captive portal.
    #
    # Even if some public wifi does properly implement the non-hijacked way and I do see Chrome
    # automatically opening the captive portal occasionally, it's not quite reliable. You'll have to go
    # through the hijacked path to handle them both. a more elegant solution than firing up my editor
    #
    # Automate this with sed should be good enough. It's still not elegant but it surely works.
    #
    # Besides, instead of setting UseDNS=false, you can also set DNSDefaultRoute=false in the .network file.
    # This, too, can disable DNS servers issued by DHCP leases. This way you can run resolvectl default-route
    # wlan0 true to temporarily enable DHCP issued DNS servers from wlan0. Maybe also run resolvectl flush-caches
    # if DNS caching accidentally prevents hijacking.
    #
    # Another issue is that your browser may be using DNS-over-HTTPS on its own / have its own DNS cache.
    # Or it may have to go through an HTTP proxy for everything where system DNS maybe doesn't matter.
    # I have a "dumb" web browser (falkon or epiphany) installed dedicated for captive portals.

    # services.resolved = {
    #   enable = false;
    #   # dnssec = "allow-downgrade";
    #   # NOTE: allow-downgrade looks to not work with captive portals, at least according to
    #   # https://github.com/systemd/systemd/issues/11240
    #   dnssec = "false";
    #   domains = ["~."];
    #   fallbackDns = ["1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" "9.9.9.9#dns.quad9.net"];
    #   dnsovertls = "false";
    #   # dnsovertls = "opportunistic";
    # };
    # services.resolved = {
    #   enable = true;
    #   dnssec = "true";
    #   domains = [ "~." ]; # "use as default interface for all requests"
    #   # (see man resolved.conf)
    #   # let Avahi handle mDNS publication
    #   extraConfig = ''
    #     DNSOverTLS=opportunistic
    #     MulticastDNS=resolve
    #   '';
    #   llmnr = "true";
    # };

    # networking.nameservers = [
    #   "1.1.1.1#cloudflare-dns.com"
    #   "8.8.8.8#dns.google"
    #   "1.0.0.1#cloudflare-dns.com"
    #   "8.8.4.4#dns.google"
    #   "2606:4700:4700::1111#cloudflare-dns.com"
    #   "2001:4860:4860::8888#dns.google"
    #   "2606:4700:4700::1001#cloudflare-dns.com"
    #   "2001:4860:4860::8844#dns.google"
    # ];

    systemd.network.links = {
      "80-iwd" = lib.mkForce {
        enable = true;
        matchConfig = {Type = "*";};
        linkConfig = {NamePolicy = "mac";};
      };
    };

    # for the case when localtimed is not loaded
    time.timeZone = lib.mkDefault "America/Los_Angeles";

    users = {
      # if i want to update passwords, this can be used
      mutableUsers = true;
      users = {
        michael = {
          hashedPasswordFile = config.sops.secrets.michael-password.path;
          # hashedPassword = "!";
          isNormalUser = true;
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = keys.laptops;
          extraGroups = [
            "wheel"
            "networkmanager"
            "video"
            "audio"
            "input"
            "i2c"
            "adbusers"
            "libvirtd"
            "plugdev"
            "dialout"
            "vboxusers"
          ];
        };
      };
      groups = {
        plugdev = {};
        adbusers = {};
      };
    };
    # users.extraGroups = {
    #   vboxusers.members = ["michael"];
    #   openrazer.members = ["michael"];
    # };
    # recomended keyring to use.
    services.gnome.gnome-keyring.enable = true;
    # Needed for sway/hyprland usage HM as per: https://nixos.wiki/wiki/Sway#Using_Home_Manager
    security.polkit.enable = true;

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        PrintMotd = true;
        AllowAgentForwarding = "yes";
      };
      # permitRootLogin = "no";
      # passwordAuthentication = false;
    };

    services.zerotierone = {
      enable = true;
      # NOTE: on first install, need to auth.
      joinNetworks = ["565799d8f65ab6a3"];
      # WARN: make sure to move this back to unstable when
      # https://github.com/NixOS/nixpkgs/pull/335676 is in unstable
      # now merged
      # package = pkgs.master.zerotierone;
    };

    services.onedrive = {
      enable = true;
      package = pkgs.onedrive.overrideAttrs (old: {
        version = "master-07-18-2025";
        src = pkgs.fetchFromGitHub {
          owner = "abraunegg";
          repo = "onedrive";
          rev = "b4179d1f27ea8a3800f003b12fe3a8c6a89e7a80";
          hash = "sha256-e+7o3U4rBKFwcAgiMdQ8c7oMzhJaQvw4B3mhqiC6XtA=";
        };
        postInstall = ''
          installShellCompletion --bash --name onedrive contrib/completions/complete.bash
          installShellCompletion --fish --name onedrive contrib/completions/complete.fish
          installShellCompletion --zsh --name _onedrive contrib/completions/complete.zsh

          substituteInPlace $out/lib/systemd/user/onedrive.service --replace-fail "sleep" "${pkgs.coreutils}/bin/sleep"
          substituteInPlace $out/lib/systemd/system/onedrive@.service --replace-fail "sleep" "${pkgs.coreutils}/bin/sleep"
        '';
      });
    };

    services.udev = {
      packages = let
        # public gpg key this is what ill match with, makes this way more secure
        # against fake yk attacks, this also adds more complexity though since any yubikeys
        # need this already tied to
        keyCheck = "rsa4096/0x2A1E939CF48AC3CC";
        command = "${pkgs.systemd}/bin/loginctl";
        # NOTE: This makes sure that only valid yubikeys are queried.
        # TODO: (low prio) Any yubikey (even a foreign one) will trigger a screen lock if its the only one inserted (and ejected).
        #   configure so that only owned yubikeys are matched with this command.
        # check=$(${
        #   lib.getExe yubikey-manager
        # } list | ${pkgs.busybox}/bin/wc -l)
        check = pkgs.writeShellScriptBin "yubicheck.sh" ''
          #!${pkgs.stdenv.shell}
          sleep 1
          check=$(gpg --card-status 2>/dev/null | grep "General key info" | cut -d " " -f 6)
          if [[ $check != ${keyCheck} ]]; then
            ${command} lock-sessions --no-ask-password
          fi
        '';
      in [
        pkgs.platformio-core
        pkgs.openocd
        (pkgs.writeTextFile {
          name = "yubikey-lock";
          text = ''
            SUBSYSTEM=="usb", ENV{PRODUCT}=="1050/407/543", ACTION=="remove", RUN+="${
              lib.getExe check
            }"
          '';
          destination = "/etc/udev/rules.d/5-yubikey-lock.rules";
        })
        (pkgs.writeTextFile {
          # to use ns-loader with the nintendo switch, this works even in with a container
          name = "ns-loader";
          text = ''
            SUBSYSTEM=="usb", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="3000", MODE="0666"
          '';
          destination = "/etc/udev/rules.d/70-ns-loader.rules";
        })
        (pkgs.writeTextFile {
          name = "i2c-udev-rules";
          text = ''ACTION=="add", KERNEL=="i2c-[0-9]*", TAG+="uaccess"'';
          destination = "/etc/udev/rules.d/70-i2c.rules";
        })
        # (pkgs.writeTextFile {
        #   name = "disable-devices-rules";
        #   text = ''
        #     # Disable fingerprint reader
        #     SUBSYSTEM=="usb", ATTRS{idVendor}=="27c6", ATTRS{idProduct}=="5395", ATTR{authorized}="0"
        #     # Disable webcam (for now, might decide later to enable)
        #     SUBSYSTEM=="usb", ATTRS{idVendor}=="0c45", ATTRS{idProduct}=="6713", ATTR{authorized}="0"
        #   '';
        #   destination = "/etc/udev/rules.d/70-device-disable.rules";
        # })
        (pkgs.writeTextFile {
          name = "oryx rules";
          text = ''
            # Rules for Oryx web flashing and live training
            KERNEL=="hidraw*", ATTRS{idVendor}=="16c0", MODE="0664", TAG+="uaccess"
            KERNEL=="hidraw*", ATTRS{idVendor}=="3297", MODE="0664", TAG+="uaccess"
          '';
          destination = "/etc/udev/rules.d/50-orxy.rules";
        })
        (pkgs.writeTextFile {
          name = "wally Rules";
          text = ''
            # Teensy rules for the Ergodox EZ Original / Shine / Glow
            ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789B]?", ENV{ID_MM_DEVICE_IGNORE}="1"
            ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789A]?", ENV{MTP_NO_PROBE}="1"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789ABCD]?", TAG+="uaccess"
            KERNEL=="ttyACM*", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789B]?", TAG+="uaccess"

            # STM32 rules for the Moonlander and Planck EZ Standard / Glow
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", TAG+="uaccess", SYMLINK+="stm32_dfu"
          '';
          destination = "/etc/udev/rules.d/50-wally.rules";
        })
        (pkgs.writeTextFile {
          name = "Realsense rules";
          text = ''
            ##Version=1.1##
            # Device rules for Intel RealSense devices (R200, F200, SR300 LR200, ZR300, D400, L500, T200)
            # SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0a80", MODE:="0666", GROUP:="plugdev", RUN+="/usr/local/bin/usb-R200-in_udev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0a66", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0aa3", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0aa2", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0aa5", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0abf", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0acb", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ad0", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="04b4", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ad1", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ad2", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ad3", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ad4", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ad5", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ad6", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0af2", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0af6", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0afe", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0aff", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b00", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b01", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b03", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b07", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b0c", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b0d", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b3a", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b3d", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b48", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b49", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b4b", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b4d", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b52", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b56", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b5b", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b5c", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b64", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b68", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b6a", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b6b", MODE:="0666", GROUP:="plugdev"

            # Intel RealSense recovery devices (DFU)
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ab3", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0adb", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0adc", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ade", MODE:="0666", GROUP:="plugdev"
            SUBSYSTEMS=="usb", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b55", MODE:="0666", GROUP:="plugdev"

            # Intel RealSense devices (Movidius, T265)
            SUBSYSTEMS=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="8087", ATTRS{idProduct}=="0af3", MODE="0666", GROUP="plugdev"
            SUBSYSTEMS=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="8087", ATTRS{idProduct}=="0b37", MODE="0666", GROUP="plugdev"
            SUBSYSTEMS=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="03e7", ATTRS{idProduct}=="2150", MODE="0666", GROUP="plugdev"

            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ad5", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor_custom", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ad5", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0af2", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0af2", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0afe", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor_custom", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0afe", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0aff", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor_custom", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0aff", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b00", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor_custom", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b00", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b01", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor_custom", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b01", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b3a", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b3a", RUN+="/bin/sh -c ' chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b3d", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b3d", RUN+="/bin/sh -c ' chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b4b", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b4b", RUN+="/bin/sh -c ' chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b4d", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b4d", RUN+="/bin/sh -c ' chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b56", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b56", RUN+="/bin/sh -c ' chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b5b", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b5b", RUN+="/bin/sh -c ' chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b5c", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b5c", RUN+="/bin/sh -c ' chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b64", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b64", RUN+="/bin/sh -c ' chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b68", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b68", RUN+="/bin/sh -c ' chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b6a", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b6a", RUN+="/bin/sh -c ' chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b6b", MODE:="0777", GROUP:="plugdev", RUN+="/bin/sh -c 'chmod -R 0777 /sys/%p'"
            DRIVER=="hid_sensor*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0b6b", RUN+="/bin/sh -c ' chmod -R 0777 /sys/%p && chmod 0777 /dev/%k'"

            # For products with motion_module, if (kernels is 4.15 and up) and (device name is "accel_3d") wait, in another process, until (enable flag is set to 1 or 200 mSec passed) and then set it to 0.
            KERNEL=="iio*", ATTRS{idVendor}=="8086", ATTRS{idProduct}=="0ad5|0afe|0aff|0b00|0b01|0b3a|0b3d|0b56|0b5c|0b64|0b68|0b6a|0b6b", RUN+="${lib.getExe pkgs.bash} -c '(major=`uname -r | cut -d \".\" -f1` && minor=`uname -r | cut -d \".\" -f2` && (([ $$major -eq 4 ] && [ $$minor -ge 15 ]) || [ $$major -ge 5 ])) && (enamefile=/sys/%p/name && [ `cat $$enamefile` = \"accel_3d\" ]) && enfile=/sys/%p/buffer/enable && echo \"COUNTER=0; while [ \$$COUNTER -lt 20 ] && grep -q 0 $$enfile; do sleep 0.01; COUNTER=\$$((COUNTER+1)); done && echo 0 > $$enfile\" | at now'"

          '';
          destination = "/etc/udev/rules.d/99-realsense-libusb.rules";
        })
        (
          pkgs.writeTextFile
          {
            name = "d4xx dfu rules";
            text = ''
              # Device rules for Intel RealSense MIPI devices.

              # DFU rules
              SUBSYSTEM=="d4xx-class", KERNEL=="d4xx-dfu*", GROUP="video", MODE="0660"
              # video links for SDK, binding for ipu6
              SUBSYSTEM=="video4linux", ATTR{name}=="DS5 mux *", RUN+="${lib.getExe pkgs.bash} -c 'rs_ipu6_d457_bind.sh > /dev/kmsg; rs-enum.sh -q > /dev/kmsg'"
            '';
            destination = "/etc/udev/rules.d/99-realsense-d4xx-mipi-dfu.rules";
          }
        )
        (pkgs.writeTextFile {
          name = "legacy oryx";
          text = ''
            # Legacy rules for live training over webusb (Not needed for firmware v21+)
            # Rule for all ZSA keyboards
            SUBSYSTEM=="usb", ATTR{idVendor}=="3297", TAG+="uaccess"
            # Rule for the Moonlander
            SUBSYSTEM=="usb", ATTR{idVendor}=="3297", ATTR{idProduct}=="1969", TAG+="uaccess"
            # Rule for the Ergodox EZ
            SUBSYSTEM=="usb", ATTR{idVendor}=="feed", ATTR{idProduct}=="1307", TAG+="uaccess"
            # Rule for the Planck EZ
            SUBSYSTEM=="usb", ATTR{idVendor}=="feed", ATTR{idProduct}=="6060", TAG+="uaccess"
          '';
          destination = "/etc/udev/rules.d/50-oryx-legacy.rules";
        })
        # These aren't needed since we are added to dialout
        # (pkgs.writeTextFile {
        #   name = "esp32 work";
        #   text = ''
        #     # Espressif USB JTAG/serial debug units
        #     ATTRS{idVendor}=="303a", ATTRS{idProduct}=="1001", MODE="660", GROUP="plugdev", TAG+="uaccess"
        #     ATTRS{idVendor}=="303a", ATTRS{idProduct}=="1002", MODE="660", GROUP="plugdev", TAG+="uaccess"
        #   '';
        #   destination = "/etc/udev/rules.d/50-esp32-serial.rules";
        # })
        # (pkgs.writeTextFile {
        #   name = "serial-udev-rules";
        #   text = ''
        #     KERNEL=="ttyACM[0-9]*",MODE:="0666"
        #     KERNEL=="ttyUSB[0-9]*",MODE:="0666"
        #   '';
        #   destination = "/etc/udev/rules.d/99-global-serial.rules";
        # })
      ];
      extraRules = '''';
    };

    services.logid.enable = true;
    services.graphicalLogin.enable = true;

    hardware.openrazer = {
      enable = false;
      #devicesOffOnScreensaver = true;
      keyStatistics = true;
      #users = [ "michael" ];
    };

    services.blueman.enable = true;
    hardware.bluetooth = {
      enable = true;
      settings = {
        General = {
          # should default to nyx/thanatos here
          Name = config.networking.hostName;
          Enable = builtins.concatStringsSep "," [
            "Control"
            "Gateway"
            "Headset"
            "Media"
            "Sink"
            "Socket"
            "Source"
          ];
          Experimental = true;
          ControllerMode = "dual";
          # ControllerMode = "bredr";
          # ControllerMode = "le";
          # FastConnectable = true;
          MultiProfile = "multiple";
          KernelExperimental = builtins.concatStringsSep "," [
            # Possible uuids
            # d4992530-b9ec-469f-ab01-6c481c47da1c (BlueZ Experimental Debug)
            # 671b10b5-42c0-4696-9227-eb28d1b049d6 (BlueZ Experimental Simultaneous Central and Peripheral)
            # 15c0a148-c273-11ea-b3de-0242ac130004 (BlueZ Experimental LL privacy)
            # 330859bc-7506-492d-9370-9a6f0614037f (BlueZ Experimental Bluetooth Quality Report)
            # a6695ace-ee7f-4fb9-881a-5fac66c629af (BlueZ Experimental Offload Codecs)
            # 6fbaf188-05e0-496a-9885-d6ddfdb4e03e (BlueZ Experimental ISO socket)

            # "15c0a148-c273-11ea-b3de-0242ac130004" # BlueZ Experimental LL privacy (not supported?)
            # "671b10b5-42c0-4696-9227-eb28d1b049d6" # BlueZ Experimental Simultaneous Central and Peripheral
            "6fbaf188-05e0-496a-9885-d6ddfdb4e03e" # BlueZ Experimental ISO socket (interferes with connection of legacy bt)
            "a6695ace-ee7f-4fb9-881a-5fac66c629af" # BlueZ Experimental Offload Codecs
          ];
          AutoConnect = false;
        };
        LE = {
          ScanIntervalSuspend = 2240;
          ScanWindowSuspend = 224;
        };
      };
      package = pkgs.bluez-experimental;
    };
    hardware.i2c.enable = true;
    hardware.graphics.extraPackages = with pkgs; [vulkan-validation-layers];
    hardware.enableAllFirmware = true;
    hardware.enableAllHardware = true;
    hardware.ksm.enable = true;

    # NOTE: as of 2024-02-29 this is the way of specifying configs.
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      lowLatency.enable = false;

      # pipewire-pulse."10-force-default" = {
      #         "pulse.cmd" = [
      #           {
      #             cmd = "set-default-sink";
      #             args = "loopback-media";
      #           }
      #           {
      #             cmd = "set-default-source";
      #             args = "rnnoise_source";
      #           }
      #         ];
      #       };
      # };
      configPackages = let
        roc-android =
          pkgs.writeTextDir "share/pipewire/pipewire.conf.d/android-roc-sink.conf"
          # fec.code = disable
          ''
             context.modules = [
              # {   name = libpipewire-module-roc-sink
              #     args = {
              #         fec.code = rs8m
              #         remote.ip = 192.168.1.18
              #         remote.source.port = 10001
              #         remote.repair.port = 10002
              #         remote.control.port = 10003
              #         sink.name = "ROC Sink"
              #         sink.props = {
              #            node.name = "roc-sink"
              #            node.description = "ROC Sink localhost"
              #            node.passive = true
              #         }
              #     }
              # }
              {   name = libpipewire-module-roc-sink
                  args = {
                      fec.code = rs8m
                      remote.ip = 192.168.86.47
                      remote.source.port = 10001
                      remote.repair.port = 10002
                      remote.control.port = 10003
                      sink.name = "ROC Sink"
                      sink.props = {
                         node.name = "roc-sink"
                         node.description = "ROC Sink im"
                         node.passive = true
                      }
                  }
              }
            ]
          '';
      in [
        # roc-android
      ];
      extraConfig.pipewire = {
        # "99-clock-rate" = {

        #   # "context.properties" = {
        #   #   "default.clock.rate" = 48000;
        #   # };
        #   monitor.alsa.rules = [
        #     {
        #       matches = [
        #         {
        #           # matches Fiio btr products, revisit if I ever get something better than the btr3k
        #           # alsa_output.usb-FiiO_FiiO_BTR3K_ABCDEF0123456789-00.analog-stereo
        #           node.name = "~alsa_ouput\.usb-FiiO_FiiO_BTR.*";
        #         }
        #       ];
        #       actions = {
        #         update-props = {
        #           # audio.rate = 48000;
        #           # audio.allowed-rates = [48000];
        #           api.alsa = {
        #             disable-batch = true;
        #             # headroom = 256;
        #           };
        #         };
        #       };
        #     }
        #   ];
        # };
        #     "20-modules" = {
        #       module.jackdbus-detect = true;
        #     };
      };
      wireplumber = {
        configPackages = let
          # enable all bt features
          # bt = pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/10-bluez.conf" ''
          #   monitor.bluez.properties = {
          #     bluez5.roles = [ a2dp_sink a2dp_source bap_sink bap_source hsp_hs hsp_ag hfp_hf hfp_ag ]
          #     bluez5.codecs = [ sbc sbc_xq aac ldac aptx aptx_hd aptx_ll aptx_ll_duplex faststream faststream_duplex ]
          #     bluez5.enable-sbc-xq = true
          #     bluez5.enable-msbc = true
          #     bluez5.hfphsp-backend = "native"
          #     # force 48000, to avoid resampling with btr3k
          #     bluez5.default.rate = 48000
          #   }
          # '';
          # R   96   2048  48000 309.8us  31.1us  0.01  0.00    0    S16LE 2 48000 alsa_output.usb-FiiO_FiiO_BTR3K_ABCDEF0123456789-00.analog-stereo
          gbuds_output =
            pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/51-gbuds_output.conf"
            ''

              monitor.alsa.rules = [
                {
                  matches = [
                    {
                      ## Matches all sources.
                      node.name = "~bluez_output.B0_54_76_4E_6B_43.1*"
                    }
                  ]
                  actions = {
                    update-props = {
                      ## this is what the it shows as the input?
                      audio.format = "S24_32"
                      ## audio.format = "S16_LE"
                      ## Force 48000 as the btr3k in dac mode does not work with anything else.
                      audio.rate = 32000

                      # Tighten up latency/buffers.
                      # api.alsa.period-num = 2
                      ## Default: 1024
                      api.alsa.period-size = 768
                      ## Default: 0
                      # api.alsa.headroom = 128

                      ## generally, USB soundcards use the batch mode
                      api.alsa.disable-batch = false
                    }
                  }
                }
              ]
            '';
          gbuds_input =
            pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/51-gbuds_input.conf"
            ''

              monitor.alsa.rules = [
                {
                  matches = [
                    {
                      ## Matches all sources.
                      node.name = "~bluez_input.B0_54_76_4E_6B_43.0*"
                    }
                  ]
                  actions = {
                    update-props = {
                      ## this is what the it shows as the input?
                      audio.format = "S24_32"
                      ## audio.format = "S16_LE"
                      ## Force 48000 as the btr3k in dac mode does not work with anything else.
                      audio.rate = 16000

                      # Tighten up latency/buffers.
                      # api.alsa.period-num = 2
                      ## Default: 1024
                      api.alsa.period-size = 768
                      ## Default: 0
                      # api.alsa.headroom = 128

                      ## generally, USB soundcards use the batch mode
                      api.alsa.disable-batch = false
                    }
                  }
                }
              ]
            '';
          fiio_audio =
            pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/51-fiio.conf"
            ''
              monitor.alsa.rules = [
                {
                  matches = [
                    {
                      ## Matches all sources.
                      node.name = "~alsa_input.usb-FiiO_FiiO_BTR3K*"
                    }
                    {
                      ## Matches all sinks.
                      node.name = "~alsa_output.usb-FiiO_FiiO_BTR3K*"
                    }
                  ]
                  actions = {
                    update-props = {
                      node.nick = "FiiO BTR3K"
                      node.description = "FiiO BTR3K"
                      audio.format = "S16_LE"
                      ## Force 48000 as the btr3k in dac mode does not work with anything else.
                      audio.rate = 48000

                      # Tighten up latency/buffers.
                      api.alsa.period-num = 2
                      ## Default: 1024
                      api.alsa.period-size = 768
                      ## Default: 0
                      api.alsa.headroom = 128

                      ## generally, USB soundcards use the batch mode
                      api.alsa.disable-batch = false
                    }
                  }
                }
              ]
            '';
          pixel_phone_input =
            pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/51-pixel_phone.conf"
            ''

              # Pipewire opus and current pixel phone do not mix, force aptx-hd for the time being
              # TODO: check once in awhile to see if this is fixed
              monitor.bluez.rules = [
                {
                  matches = [
                    {
                      node.name = "~bluez_card.D4_3A_2C_99_CB_B2"
                    }
                  ]
                  actions = {
                    update-props = {
                      api.bluez5.codec = "aptx_hd"
                    }
                  }
                }
              ]
            '';
        in [
          fiio_audio
          # gbuds_input
          # pixel_phone_input
        ];
        extraConfig = {
          # cannot force this 💀
          # need to change this manually ;-;
          # INFO: when changing to opus bitrate changes from
          #   "51-pixel7pro" = {
          #     "monitor.bluez.rules" = [
          #       {
          #         matches = [{"device.name" = "bluez_card.D4_3A_2C_99_CB_B2";}];
          #         actions = {
          #           # update-props = {
          #           "apply-properties" = {
          #             "bluez5.codecs" = [
          #               "aac"
          #               "aac_eld"
          #               "aptx"
          #               "aptx_hd"
          #               "aptx_ll"
          #               "aptx_ll_duplex"
          #               "faststream"
          #               "faststream_duplex"
          #               "lc3"
          #               "lc3plus_h3"
          #               "ldac"
          #               "opus_05"
          #               "opus_05_51"
          #               "opus_05_71"
          #               # One of these codecs gives me issues connecting to the pixel phone
          #               # "opus_05_duplex"
          #               # "opus_05_pro"
          #               # "opus_g"
          #               "sbc"
          #               "sbc_xq"
          #             ];
          #           };
          #         };
          #       }
          #     ];
          #   };
          # };
          "50-bluez" = {
            "bluetooth.autoswitch-to-headset-profile" = false;

            "monitor.bluez.rules" = [
              {
                matches = [{"device.name" = "~bluez_card.*";}];
                actions = {
                  update-props = {
                    #   "bluez5.auto-connect" = [
                    #     "a2dp_sink"
                    #     "a2dp_source"
                    #   ];
                    "bluez5.hw-volume" = [
                      "a2dp_sink"
                      "a2dp_source"
                    ];
                  };
                };
              }
            ];

            # INFO: see https://docs.pipewire.org/page_man_pipewire-props
            # Currently some headsets (Sony WH-1000XM3) are not working with both hsp_ag and hfp_ag enabled, so by default we enable only HFP.
            "monitor.bluez.properties" = {
              "bluez5.roles" = [
                "a2dp_sink"
                "a2dp_source"
                # NOTE: for some 48 + src does not work see:
                # https://github.com/bluez/bluez/issues/793#issuecomment-2050379540
                # le audio (with the buds 2 pro) only work with bap_source opened
                "bap_sink"
                "bap_source"
                "hfp_ag"
                "hfp_hf"
                "bap_bcast_sink"
                "bap_bcast_source"
              ];

              "bluez5.codecs" = [
                "aac"
                "aac_eld"
                "aptx"
                "aptx_hd"
                "aptx_ll"
                "aptx_ll_duplex"
                "faststream"
                "faststream_duplex"
                "lc3"
                "lc3plus_h3"
                "ldac"
                "opus_05"
                "opus_05_51"
                "opus_05_71"
                # One of these codecs gives me issues connecting to the pixel phone
                "opus_05_duplex"
                "opus_05_pro"
                "opus_g"
                "sbc"
                "sbc_xq"
              ];

              "bluez5.enable-sbc-xq" = true;
              "bluez5.enable-msbc" = true;
              "bluez5.hfphsp-backend" = "native";
              # "bluez5.hfphsp-backend" = "none";
            };
          };
        };
      };
    };

    services.udisks2.enable = true;
    services.thermald.package = thermald;
    services.upower = {
      enable = true;
      criticalPowerAction = "Hibernate";
      percentageCritical = 10;
    };
    services.gpsd.enable = true;

    environment.systemPackages = with pkgs;
      [
        thermald
        ##swaylockCheck
        virt-manager
        # uses qtwebengine, which takes a bit to build
        # polychromatic
        fwupd
        mosh
        wget
        curl
        gcc_multi
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
        nix-du
        # dot command needed by nix-du
        graphviz
        # check whats compiling
        nix-top
        # scripts can set dependencies inside themselves
        # i: https://github.com/madjar/nixbang
        nixbang
        # create oci images from repos
        # gh: https://github.com/railwayapp/nixpacks
        # LINK: https://nixpacks.com/docs/getting-started
        nixpacks
        # dependicies as a tree
        nix-tree
        nix-diff
        # hash calulation for nixpkgs/docker/github
        nix-prefetch-scripts
        # rnix-hashes unmaintained 2024-01-15
        nix-prefetch-docker
        nix-prefetch-github
        # Extra packages to check cpu states

        wally-cli
        veracrypt
        exfatprogs
        file
        # needed for scale
        zoom-us

        # for signal
        master.signal-cli
        scli
        signal-desktop

        libnotify
        # image viewer
        feh
        fastfetch
        nix-output-monitor
        # figma-linux
        rquickshare
        stable.libreoffice
        sbctl
        networkmanagerapplet
        libva-utils
        mesa-demos
        mindustry

        lutris
        heroic
      ]
      ++ (with config.boot.kernelPackages; [
        #
        turbostat
        # TODO: BORKED AS OF 2025-08-27
        # temp monitor
        # tmon
        # usbip
        lm_sensors
      ]);

    yubiAuth.enable = true;

    # environment.pathsToLink = ["/share/zsh"];

    fonts = {
      packages = with pkgs;
        [
          noto-fonts
          # 2025-11-05: noto-fonts-emoji to  noto-fonts-color-emoji
          noto-fonts-color-emoji
          # TODO: (low prio) might change this to the default nerdfonts instead of rebuilding with windows fonts as well
          # (nerdfonts.overrideAttrs (prev: {enableWindowsFonts = true;}))
          # nerdfonts
          winePackages.fonts
          # 2025-11-05: vistafonts to vista-fonts
          vista-fonts
          powerline-fonts
          powerline-symbols
          font-awesome
          corefonts
          # Manrope: UI font for the surface-dots chrome adaptation (theme seam
          # fonts.ui). nixpkgs removed pkgs.manrope (source pulled), so vendor the
          # variable TTF from google/fonts. FUTURE: fold into a shared google-fonts
          # set, probably in flake-playground (see memory: google-fonts-pkg-module).
          (stdenvNoCC.mkDerivation {
            pname = "manrope";
            version = "2025-04-14";
            src = fetchurl {
              url = "https://github.com/google/fonts/raw/fb629caaa15ad25c051089c98f09cf6c8e30a86b/ofl/manrope/Manrope%5Bwght%5D.ttf";
              name = "Manrope-variable.ttf";
              hash = "sha256-0GOb5F0K8255gXJBnXvRc8S9Tynit2y7adsdEb+LCkA=";
            };
            dontUnpack = true;
            installPhase = ''
              runHook preInstall
              dest=$out/share/fonts/truetype
              mkdir -p $dest
              cp $src $dest/Manrope-variable.ttf
              runHook postInstall
            '';
            meta = {
              description = "Manrope font from Google Fonts";
              license = lib.licenses.ofl;
              platforms = lib.platforms.all;
            };
          })
          # pkgs.nerd-fonts._0xproto
          # pkgs.nerd-fonts.droid-sans-mono
        ]
        ++ builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);
      enableGhostscriptFonts = true;
      enableDefaultPackages = true;
      fontconfig = {
        subpixel = {lcdfilter = "default";};
        defaultFonts.monospace = ["JetBrainsMono NFM"];
      };
    };
    desktop = {
      common.enable = true;
      wayland.laptop = true;
    };

    # TODO: move this to its own file
    programs.kdeconnect.enable = false;
    programs.captive-browser = {
      enable = true;
      # WARN: this needs to be changed per wifi interface
      interface = "wlxc03c597743d1";
    };

    virt.alt.enable = true;
    boot.kernelPatches = [
      # {
      # # does not work! need to port patch
      #   name = "Add support for TX timestamping in ISO/SCO/L2CAP sockets.";
      #   patch = pkgs.fetchurl {
      #     url = "https://lore.kernel.org/linux-bluetooth/cover.1710440392.git.pav@iki.fi/t.mbox.gz";
      #     hash = "sha256-J/Wk4PFDn0az9GflUJ3B6jgFOssQuCrPjFK/jFjwimY=";
      #   };
      # }

      # NOTE: This patch also needs to be ported or checked if its already merged
      # {
      #   name = "[PATCH] Bluetooth: add experimental BT_POLL_ERRQUEUE socket option";
      #
      #   # NOTE: TIL PATCHES CAN CHANGE HASHES
      #   patch = pkgs.fetchurl {
      #     url = "https://lore.kernel.org/linux-bluetooth/134027f3cbaeb7095d080c27cd4b1053d2eb560e.1710440392.git.pav@iki.fi/t.mbox.gz";
      #     # hash = "sha256-j5rGYx/W+IekMhCDuevbLImZ5JtEDyMVyg0qKivZ5Lc=";
      #     hash = "sha256-J/Wk4PFDn0az9GflUJ3B6jgFOssQuCrPjFK/jFjwimY=";
      #   };
      # }
    ];

    # home-manager.users."michael" = let
    #
    #    homeManagerModules =
    #      baseModules
    #      ++ [inputs.nixneovim.nixosModules.homeManager];
    # in  {
    # imports = [ ../../hm/home.nix inputs.hyprland.homeManagerModules.default ] ++ outputs.homeManagerModules ++ outputs.overlayModule;
    # };
    #
    # This block is for autotimezone setup
    services.localtimed.enable = true;
    # ssssh v2
    services.geoclue2 = let
      # Arch linux gmaps key 🩵
      gkey = "AIzaSyDwr302FpOSkGRpLlUpPThNTDPbXcIn_FM";
    in {
      enable = true;
      enableWifi = true;
      geoProviderUrl = "https://www.googleapis.com/geolocation/v1/geolocate?key=${gkey}";
      appConfig = let
        mkConfig = {users ? []}: {
          inherit users;
          isAllowed = true;
          isSystem = true;
        };
      in {
        "where-am-i" = mkConfig {};
        general = mkConfig {};
      };
    };
    services.avahi = {
      enable = true;
    };

    programs.gamescope = {
      enable = true;
      capSysNice = true;
    };
    programs.gamemode = {
      enable = true;
      enableRenice = true;
    };
    programs.steam = {
      enable = true;
      gamescopeSession.enable = true;
      protontricks.enable = true;
    };

    # services.logind.extraConfig = ''
    #   HandlePowerKey=suspend
    #   HandlePowerKeyLongPress=powerfoff
    # '';
    services.logind.settings.Login = {
      HandlePowerKey = "suspend";
      HandlePowerKeyLongPress = "poweroff";
    };
    services.input-remapper = {
      enable = true;
      enableUdevRules = true;
    };
    hardware.cynthion.enable = true;
    hardware.zsa = {
      wally.enable = true;
      oryx.enable = true;
    };
    sops.defaultSopsFile = ../../secrets/default.yaml;
    sops.defaultSopsFormat = "yaml";
    sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    sops.age.keyFile = "/var/lib/sops-nix/key.txt";
    sops.age.generateKey = true;
    sops.secrets = {
      michael-password = {
        # owner = config.users.users.michael.name;
        neededForUsers = true;
      };
    };
    # sops.secrets.users.michael = {
    #   password = {
    #     owner = config.users.users.michael.name;
    #   };
    # };
    services.dbus.implementation = "broker";

    environment.pathsToLink = ["/share/zsh" "/share/xdg-desktop-portal" "/share/applications"];

    programs.yubikey-touch-detector.enable = true;
    qt = {
      enable = true;
      platformTheme = "gtk2";
    };
    programs.zoxide.enable = true;

    boot.binfmt.emulatedSystems = [
      "i686-linux"
      "aarch64-linux"
      "riscv64-linux"
    ];
    nix.settings.extra-platforms = config.boot.binfmt.emulatedSystems;

    # 2026-06-29: WARN: bypassing issue with xanmod  not building a bzimage by default
    system.boot.loader.kernelFile = "vmlinuz";

    # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
    # system.stateVersion = "23.11";
    system.stateVersion = "24.11";
  };
}
