# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  fsOptions = ["compress=zstd" "noatime"];
  cfg = config;
  keys = import ../../helpers/keys.nix;
in {
  imports = [
    # Include the results of the hardware scan.
    inputs.hardware.nixosModules.common-cpu-amd
    inputs.hardware.nixosModules.common-cpu-amd-pstate
    inputs.hardware.nixosModules.common-pc
    # TODO: (med prio) Revisit this and check if this is still needed.
    # {services.xserver.libinput.enable = lib.mkForce false;}
    inputs.hardware.nixosModules.common-pc-ssd
    ./hardware-configuration.nix
    ../../features/nixos/common
    # ../../features/nixos/kernel
    # ../../features/nixos/virtualization
    ../../features/nixos/common/deploy.nix
    ../../features/nixos/server
    ../../features/nixos/server/base.nix
    ../../helpers/caches.nix
    ./disk-config.nix
  ];

  services.eternal-terminal.enable = true;

  boot.kernelPackages = pkgs.linuxPackages;
  # kernel.mod.kernelPkg = pkgs.linuxPackages;
  # virt.vfio.enable = true;
  # kernel.patch.sm.enable = true;
  # kernel.patch.timer.enable = false;
  # kernel.patch.noFlr.enable = true;
  # kernel.mod.native.enable = true;
  # NOTE: Use systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.timeout = 3;
  # NOTE: We are running on btrfs, make sure boot supports this.
  # We are also using zfs in this system. Make sure that the zfs package is supported for the kernel used.
  boot.supportedFilesystems = ["btrfs" "zfs"];
  # NOTE: Make sure swap is unlocked. THIS IS NEEDED FOR BOOT!
  # boot.initrd.luks.devices."swap".device = "/dev/disk/by-uuid/85373c67-11f2-49c6-85c4-b9b05811eb6b";
  boot.initrd = {
    availableKernelModules = ["cryptd"];
    kernelModules = ["igb"];
    #preLVMCommands = lib.mkOrder 400 "sleep 1";
    # TODO: (high prio) (research) check if it is possible to work into zerotier into initrd.
    network = {
      enable = true;
      flushBeforeStage2 = true;
      udhcpc.enable = true;
      ssh = {
        enable = true;
        port = 2222;
        authorizedKeys = keys.initrd;
        ignoreEmptyHostKeys = true;
        # NOTE: MAKE SURE THESE FILES EXIST ON SYSTEM ELSE NO BOOT IS POSSIBLE
        # TODO: (high prio) (research) Include host keys here. Prereq for this will be 'sops-nix'.
        # hostKeys = [
        #   # NOTE: on charon
        #   "/etc/secrets/initrd/ssh_host_rsa_key"
        #   # NOTE: yubi based key
        #   "/etc/secrets/initrd/ssh_host_ed25519_key"
        # ];
      };
    };
  };
  boot.kernelParams = [
    # "boot.shell_on_fail"
    # "fsck.mode=force"
    # "fsck.repair=yes"
    "zfs_force=1"

    # TODO: (med prio) Revisit this, this was probably the bug encountered when resetting sm22662 nvme drives.
    # NOTE: Need to isolate ex920 at initial boot. Otherwise it wont be able to be grabbed at runtime.
    "vfio_pci.ids=126f:2262"
  ];
  # boot.extraModulePackages = with config.boot.kernelPackages; [ zfs ];
  boot.zfs = {
    requestEncryptionCredentials = true;
    # extraPools = ["zmedia" "zbackup"];
  };
  services.zfs.autoScrub.enable = true;
  # TODO: (high prio) setup zfs drives.

  hardware.enableAllFirmware = true;
  hardware.ksm.enable = true;
  # TODO: (med prio) (research) Re-enable ntfs3 support.
  #kernel-mod.ntfs3.enable = true;

  ## hardware-configuration overrides
  # fileSystems = {
  #   "/".options = fsOptions;
  #   "/home".options = fsOptions;
  #   "/nix".options = fsOptions;
  #   "/persist".options = fsOptions;
  #   "/var/log" = {
  #     options = fsOptions;
  #     neededForBoot = true;
  #   };
  # };
  networking = {
    useDHCP = false;
    bridges = {
      br-vm = {
        # This is dependent on hardware and *will* change when i change ethernet devices
        interfaces = ["enxa8a159020d7e"];
        # rstp = false;
      };
    };
    interfaces = {
      br-vm = {
        useDHCP = true;
        ipv4.addresses = [
          {
            address = "192.168.1.5";
            prefixLength = 24;
          }
        ];
      };
    };
    defaultGateway = {
      address = "192.168.1.1";
      # interface = "br-vm";
    };
    # hostId is for zfs
    hostId = "7f5bd178";
    hostName = "kore";
    networkmanager = {enable = true;};
    firewall = {
      enable = true;
      allowedTCPPorts = [
        # iscsi
        3260
        # k3s
        10250
        #gpsd
        2947
      ];
      #   allowedUDPPorts = [
      #   2947
      # ];
      extraCommands = ''iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns'';
    };
  };
  nixpkgs = {
    overlays = [
      # overlay skeleton
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
      # for ccache shit
      (self: super: {
        ccacheWrapper = super.ccacheWrapper.override {
          extraConfig = ''
            export CCACHE_COMPRESS=1
            export CCACHE_DIR="${config.programs.ccache.cacheDir}"
            export CCACHE_UMASK=007
            if [ ! -d "$CCACHE_DIR" ]; then
              echo "====="
              echo "Directory '$CCACHE_DIR' does not exist"
              echo "Please create it with:"
              echo "  sudo mkdir -m0770 '$CCACHE_DIR'"
              echo "  sudo chown root:nixbld '$CCACHE_DIR'"
              echo "====="
              exit 1
            fi
            if [ ! -w "$CCACHE_DIR" ]; then
              echo "====="
              echo "Directory '$CCACHE_DIR' is not accessible for user $(whoami)"
              echo "Please verify its access permissions"
              echo "====="
              exit 1
            fi
          '';
        };
      })
    ];
  };
  zramSwap = {
    memoryPercent = 10;
  };

  users.users.sysadmin = {
    openssh.authorizedKeys.keys = keys.all;
  };
  # TODO: (med prio) move this away from server config, ideally makes this a feature option.
  programs.zsh = {
    enableBashCompletion = true;
    enableCompletion = true;
    enableGlobalCompInit = true;
    histSize = 100000;
  };

  # nix = {
  #   # This will add each flake input as a registry
  #   # To make nix3 commands consistent with your flake
  #   registry = lib.mapAttrs (_: value: {flake = value;}) inputs;
  #
  #   # This will additionally add your inputs to the system's legacy channels
  #   # Making legacy nix commands consistent as well, awesome!
  #   nixPath =
  #     lib.mapAttrsToList (key: value: "${key}=${value.to.path}")
  #     config.nix.registry;
  #
  #   settings = {
  #     # Enable flakes and new 'nix' command
  #     experimental-features = "nix-command flakes";
  #     # Deduplicate and optimize nix store
  #     auto-optimise-store = true;
  #     trusted-users = ["deploy" "sysadmin"];
  #   };
  # };

  # run without xorg
  services.xserver.enable = lib.mkForce false;
  # install nvidia drivers
  services.xserver.videoDrivers = ["nvidia"];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    nvidiaPersistenced = false;
    open = false;
  };
  environment.pathsToLink = ["/share/zsh"];

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkbOptions in tty.
  # };

  # Configure keymap in X11
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    # wget
    direnv
    swtpm
  ];
  # needed for ccache (ie linux kernel builds are long af)
  programs.ccache.enable = false;

  programs.ccache.packageNames = [
    # "ffmpeg"

    # TODO: () implement https://github.com/NixOS/nixpkgs/issues/153343#issuecomment-1254656444

    # "linuxPackages.kernel"
    # "linux"
    # "linuxPackages"
    # "linuxKernel.kernels.linux"

    # "linux_latest"
    # "linuxPackages_latest"
    # "linuxKernel.kernels.linux_latest"
    #
    # "linux_testing"
    # "linuxPackages_testing"
    # "linuxKernel.kernels.linux_testing"

    # NOTE: (low prio) because multiple OVMF versions, this doesnt work (?) need to investigate further
    # "qemu"
  ];

  # BinFMT - Enable seemless VM-based cross-compilation
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "riscv64-linux"
    "armv7l-linux"
  ];

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
  services.samba = {
    enable = true;
    # securityType = "user";
    openFirewall = true;
    nmbd.enable = true;
    # settings = {
    #   global = {
    #     "workgroup" = "WORKGROUP";
    #     "server string" = cfg.networking.hostName;
    #     "netbios name" = cfg.networking.hostName;
    #     "security" = "user";
    #     "hosts allow" = "192.168.0 127.0.0.1 localhost 172.30.0";
    #     "hosts deny" = "0.0.0.0/0";
    #     "guest account" = "nobody";
    #     "map to guest" = "bad user";
    #   };
    #   "zbackup" = {
    #     "path" = "/run/media/backup";
    #     "browseable" = "yes";
    #     "read only" = "no";
    #     "writable" = "yes";
    #     "guest ok" = "yes";
    #     "create mask" = "0644";
    #     "directory mask" = "0755";
    #     # "force user" = "nobody";
    #     # "force group" = "groups";
    #   };
    #   "zmedia" = {
    #     "path" = "/run/media/media";
    #     "browseable" = "yes";
    #     "read only" = "no";
    #     "writable" = "yes";
    #     "guest ok" = "yes";
    #     "create mask" = "0644";
    #     "directory mask" = "0755";
    #   };
    #   "timemachine" = {
    #     "path" = "/run/media/tm";
    #     "browseable" = "yes";
    #     "writable" = "yes";
    #     "valid users" = "tm";
    #     "fruit:aapl" = "yes";
    #     "fruit:time machine" = "yes";
    #     "vfs objects" = "catia fruit streams_xattr";
    #   };
    # "private" = {
    #   "path" = "/mnt/Shares/Private";
    #   "browseable" = "yes";
    #   "read only" = "no";
    #   "guest ok" = "no";
    #   "create mask" = "0644";
    #   "directory mask" = "0755";
    #   "force user" = "username";
    #   "force group" = "groupname";
    # };
    # };
    settings = let
      commonOpts = {
        "browseable" = "yes";
        "read only" = "no";
        "writable" = "yes";
        "guest ok" = "yes";
        "create mask" = 0664;
        "directory mask" = 0775;
        "veto files" = "/._*/.DS_Store/";
        "delete veto files" = "yes";
      };
    in {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "${cfg.networking.hostName}";
        "netbios name" = "${cfg.networking.hostName}";
        security = "user";
        "hosts allow" = ["192.168.1." "127.0.0.1" "localhost" "172.30.0."];
        # "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
        # for  rackmount version of the mac pro
        "fruit:model" = "MacPro7,1@ECOLOR=226,226,224";
        "client min protocol" = "smb2";
        "client max protocol" = "smb3";
        ###########################################################################################################
        # APPLE specific config
        # from: https://medium.com/@augusteo/fixing-slow-macos-finder-connection-to-linux-samba-server-ed7e5ea784c1

        "fruit:aapl" = "yes";
        "fruit:encoding" = "native";
        "fruit:locking" = "none";
        "fruit:metadata" = "stream";
        "fruit:resource" = "xattr";
        "ea support" = "yes";
        "fruit:advertise_fullsync" = "true";
        "smb2 leases" = "yes";
        "durable handles" = "yes";
        ##########################################################################################################
        "invalid users" = [
          "root"
          "deploy"
        ];
      };
      "backup" =
        {
          "path" = "/run/backup/backup";
        }
        // commonOpts;
      "media" =
        {
          "path" = "/run/media/media";
        }
        // commonOpts;
      "TimeMachine" = {
        path = "/run/media/tm";
        "browseable" = "yes";
        "writable" = "yes";
        "valid users" = "tm";
        "fruit:time machine" = "yes";
        "vfs objects" = "catia fruit streams_xattr";
      };
    };
    # extraConfig = ''
    #   [global]
    #     workgroup = WORKGROUP
    #     server string = ${cfg.networking.hostName}
    #     netbios name = ${cfg.networking.hostName}
    #     security = user
    #     hosts allow = 192.168.1., 127.0.0.1, localhost, 172.30.0.
    #     # hosts deny = 0.0.0.0/0
    #     guest account = nobody
    #     map to guest = bad user
    #     # for  rackmount version of the mac pro
    #     fruit:model = MacPro7,1@ECOLOR=226,226,224
    #     client min protocol = smb2
    #     client max protocol = smb3
    #     ###########################################################################################################
    #     # APPLE specific config
    #     # from: https://medium.com/@augusteo/fixing-slow-macos-finder-connection-to-linux-samba-server-ed7e5ea784c1
    #
    #     fruit:aapl = yes
    #     fruit:encoding = native
    #     fruit:locking = none
    #     fruit:metadata = stream
    #     fruit:resource = xattr
    #     ea support = yes
    #     fruit:advertise_fullsync = true
    #     smb2 leases = yes
    #     durable handles = yes
    #     ##########################################################################################################
    #
    #
    #   [zbackup]
    #     path = /run/media/backup
    #     browseable = yes
    #     read only = no
    #     writable = yes
    #     guest ok = yes
    #     create mask = 0644
    #     directory mask = 0755
    #     veto files = /._*/.DS_Store/
    #     delete veto files = yes
    #   [zmedia]
    #     path = /run/media/media
    #     browseable = yes
    #     read only = no
    #     writable = yes
    #     guest ok = yes
    #     create mask = 0644
    #     directory mask = 0755
    #     veto files = /._*/.DS_Store/
    #     delete veto files = yes
    #   [TimeMachine]
    #     path = /run/media/tm
    #     browseable = yes
    #     writable = yes
    #     valid users = tm
    #     fruit:time machine = yes
    # '';

    # [global]
    #   workgroup = WORKGROUP
    #   server string = ${cfg.networking.hostName}
    #   fruit:aapl = yes
    #   vfs objects = catia fruit streams_xattr
    #   fruit:metadata = stream
    #   fruit:encoding = native
    #   fruit:time machine = yes
    # [zbackup]
    #   path = /run/media/backup
    #   browseable = yes
    #   writable = yes
    #   # decide if i want anon access,
    #   # this makes it real easy to login, but i bring in multiple users, then i need to lock this down
    #   # guest ok = no
    #
    # [zmedia]
    #   path = /run/media/media
    #   browseable = yes
    #   writable = yes
    #   # decide if i want anon access,
    #   # this makes it real easy to login, but i bring in multiple users, then i need to lock this down
    #   # guest ok = no
    #
    # [TimeMachine]
    #   path = /run/media/tm
    #   browseable = yes
    #   writable = yes
    #   valid users = tm
    #   fruit:time machine = yes
    # zbackup/backup on /run/media/backup type zfs (rw,relatime,xattr,noacl,casesensitive)
    # zmedia/media on /run/media/media type zfs (rw,relatime,xattr,noacl,casesensitive)

    # invalidUsers = [
    #   "root"
    #   "deploy"
    # ];
  };
  services.uptimed.enable = true;
  services.avahi.enable = true;

  # nixpkgs.overlays = [
  # ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
}
