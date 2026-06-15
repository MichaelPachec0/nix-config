# Channel-agnostic core of the integrated home-manager NixOS module
# (useGlobalPkgs = true), while the same modules remain usable standalone via
# flake.nix homeConfigurations.* (see docs/hm-nixos-integration.md).
#
# Imported by ./default.nix (unstable) and ./stable.nix (stable), each of which
# adds the matching home-manager NixOS module.
{
  inputs,
  outputs,
  lib,
  config,
  ...
}: let
  cfg = config.local.hm;
  overlays = import ../../../helpers/overlays.nix {inherit inputs;};
  homeLib = import ../../../helpers/home.nix {inherit inputs;};
in {
  options.local.hm = {
    enable =
      lib.mkEnableOption
      "integrated home-manager (useGlobalPkgs) for a system user";
    user = lib.mkOption {
      type = lib.types.str;
      default = "michael";
      description = "User whose home-manager config is managed by NixOS.";
    };
    entry = lib.mkOption {
      type = lib.types.path;
      default = ../../../hm/home.nix;
      description = "Primary home-manager entrypoint module.";
    };
    perHost = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      description = "Host-specific home-manager modules, e.g. [./hm/home-nyx.nix].";
    };
    desktop = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Desktop host: pulls in hyprland + the desktop HM modules and hoists the
        HM-only overlay delta onto the system pkgs. Servers (false) use plain
        nixpkgs in their HM config.
      '';
    };
    channel = lib.mkOption {
      type = lib.types.enum ["unstable" "stable"];
      default = "unstable";
      description = "nixpkgs/home-manager channel this host tracks.";
    };
  };

  config = lib.mkIf cfg.enable {
    # useGlobalPkgs => HM reuses the system pkgs. Desktop hosts need the HM-only
    # overlay delta (custom vim plugins, LSP servers, claude-code) on the system;
    # servers reference only plain nixpkgs from their HM config, so skip it.
    nixpkgs.overlays =
      lib.optionals cfg.desktop overlays.${cfg.channel}.hmIntegrationOverlays;

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      # keep activation from aborting on pre-existing dotfiles it would overwrite
      backupFileExtension = "hm-bak";
      extraSpecialArgs = {
        inherit inputs outputs;
        standalone = false;
      };
      users.${cfg.user}.imports = homeLib.mkHomeModules {
        inherit (cfg) entry perHost desktop channel;
        standalone = false;
      };
    };
  };
}
