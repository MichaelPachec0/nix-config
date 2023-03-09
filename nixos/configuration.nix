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
    # Import your generated (nixos-generate-config) hardware configuration
    ./hardware-configuration.nix
  ];
  boot.initrd.availableKernelModules = [
    # fast decrypt for luks
    "aesni_intel"
    "cryptd"
  ];
  # make sure to compile broadcom kernel modules, needed for the bcm4360
  boot.kernelModules = [ "wl" ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ broadcom_sta ];
  boot.blacklistedKernelModules = [ "b43" "bcma" ];
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

  # FIXME: Add the rest of your current configuration

  # TODO: Set your hostname
  networking.hostName = "nyx";
  networking.networkmanager.enable = true;
  networking.firewall.enable = false;

  # TODO: This is just an example, be sure to use whatever bootloader you prefer
  boot.loader = {
    systemd-boot = {
      enable = true;
      memtest86.enable = true;
    };
    efi.canTouchEfiVariables = false;
  };

  time.timeZone = "America/Los_Angeles";

  # TODO: Configure your system-wide user settings (groups, etc), add more users as needed.
  users.users = {
    # FIXME: Replace with your username
    michael = {
      hashedPassword =
        "$6$WXBvFlgvwtcGIdYg$IS.Rii0vfzj2j5nDqpPm.a0maMqRYTQ2u/kaRaaO2Css/rzsSYghXPhlVOFAUTma1UU19oSCvccLfe1LRMF8T/";
      isNormalUser = true;
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [
        # TODO: Add your SSH public key(s) here, if you plan on using SSH to connect
      ];
      extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    };
  };

  services.openssh = {
    enable = true;
    # Allow root login through SSH.
    permitRootLogin = "no";
    # SSH using password
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

  environment.systemPackages = with pkgs; [
    mosh
    wget
    curl
    nerdfonts
    gcc_multi
    openssl

  ];

  fonts.fonts = with pkgs; [ noto-fonts noto-fonts-emoji nerdfonts ];

  fonts.fontconfig.defaultFonts.monospace =
    [ "Iosevka Nerd Font Complete Mono" ];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "21.11";
}
