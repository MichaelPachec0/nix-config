# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, inputs, ... }:
let fsOptions = [ "compress=zstd" "noatime" ];
in {
  imports = [ # Include the results of the hardware scan.
    inputs.hardware.nixosModules.common-cpu-amd
    inputs.hardware.nixosModules.common-cpu-amd-pstate
    inputs.hardware.nixosModules.common-pc
    { services.xserver.libinput.enable = lib.mkForce false; }
    inputs.hardware.nixosModules.common-pc-hdd
    inputs.hardware.nixosModules.common-pc-ssd
    ./hardware-configuration.nix
    ../../features/nixos/common
    ../../features/nixos/kernel
    ../../features/nixos/common/deploy.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  # We are running on btrfs, make sure boot supports this.
  boot.supportedFilesystems = [ "btrfs" ];
  # Make sure swap is unlocked.
  boot.initrd.luks.devices."swap".device =
    "/dev/disk/by-uuid/92488ec8-0bb3-4e9c-9c54-372ad59bb2d8";
  boot.initrd.availableKernelModules = [
    # fast decrypt for luks
    "aesni_intel"
    "cryptd"
  ];
  hardware.enableAllFirmware = true;

  ## hardware-configuration overrides
  fileSystems = {
    # hardware-configuration.nix did not enable these options, enable them here
    "/".options = fsOptions;
    "/home".options = fsOptions;
    "/nix".options = fsOptions;
    "/persist".options = fsOptions;
    "/var/log" = {
      options = fsOptions;
      neededForBoot = true;
    };
  };
  networking = {
    hostName = "kore";
    networkmanager = { enable = true; };
    nameservers = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
    firewall.enable = true;
  };
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

  time.timeZone = "America/Los_Angeles";

  users = {
    mutableUsers = false;
    users = {
      sysadm = {
        hashedPassword =
          "$6$WXBvFlgvwtcGIdYg$IS.Rii0vfzj2j5nDqpPm.a0maMqRYTQ2u/kaRaaO2Css/rzsSYghXPhlVOFAUTma1UU19oSCvccLfe1LRMF8T/";
        isNormalUser = true;
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = [
          # 718
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAICFSUN6IGskLmeq7ip+oTbYuE+WRLcbYGGGOAyH/ECWaAAAABHNzaDo= michael@nyx"
          # 828
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIAKEnIsOFEp1Lx9XwZRVN+iRKyCKRiy4U9kw1JWH1UAYAAAABHNzaDo= michael@nyx"
        ];
        extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
      };
    };
  };
  services.openssh = {
    enable = true;
    permitRootLogin = "no";
    passwordAuthentication = false;
  };
  services.zerotierone = {
    enable = true;
    joinNetworks = [ "565799d8f65ab6a3" ];
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

  # run without xorg
  services.xserver.enable = lib.mkForce false;
  # install nvidia drivers
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.opengl.enable = true;
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    nvidiaPersistenced = true;
  };

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
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
  # environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #   wget
  # ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It’s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

}

