# Shared base configuration for all server hosts (kore, atlas, selene).
#
# Extracted verbatim from the per-host configuration.nix files. Each server
# imports this module and keeps only host-specific config (bootloader, hardware,
# disk layout, networking IPs/hostName/firewall, its OWN sysadmin SSH keys and
# shell, and any application stack).
#
# NOTE: this module intentionally does NOT import ../server (eternal-terminal /
# languageTool) so it does not change behaviour for hosts that don't already
# import it (atlas).
{
  inputs,
  config,
  lib,
  ...
}: {
  systemd.services."zerotierone" = {after = ["dhcpcd.service"];};

  zramSwap.enable = true;

  systemd.network.links = {
    "80-iwd" = lib.mkForce {
      enable = true;
      matchConfig = {Type = "*";};
      linkConfig = {NamePolicy = "mac";};
    };
  };

  # Common sysadmin user attributes. Each host adds its own
  # `users.users.sysadmin.openssh.authorizedKeys.keys` (and `shell`), which
  # merge with these.
  users.mutableUsers = false;
  users.users.sysadmin = {
    # TODO: (high prio) regenerate password.
    hashedPassword = "***PASSWORD-HASH-REMOVED***";
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "video" "audio" "input" "builders"];
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
    };
  };

  services.zerotierone = {
    enable = true;
    joinNetworks = ["565799d8f65ab6a3"];
  };

  nix = {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Opinionated: disable global registry
      flake-registry = "";
      # Workaround for https://github.com/NixOS/nix/issues/9574
      nix-path = config.nix.nixPath;
      # Deduplicate and optimize nix store
      auto-optimise-store = true;
      trusted-users = ["deploy" "sysadmin"];
    };
    # Opinionated: disable channels
    channel.enable = false;
  };

  nixpkgs.config.allowUnfree = true;

  services.uptimed.enable = true;
  time.timeZone = "America/Los_Angeles";
  networking.nameservers = ["1.1.1.1" "8.8.8.8" "9.9.9.9"];

  system.stateVersion = "24.11";
}
