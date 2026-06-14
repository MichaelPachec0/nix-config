# Reusable NixOS module that builds the user's home-manager config as part of the
# system (useGlobalPkgs = true), while the same modules remain usable standalone
# via flake.nix homeConfigurations.* (see docs/hm-nixos-integration.md).
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
  imports = [inputs.home-manager.nixosModules.home-manager];

  options.local.hm = {
    enable =
      lib.mkEnableOption
      "integrated home-manager (useGlobalPkgs) for the primary desktop user";
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
      description = "Desktop host: pulls in hyprland + the desktop HM modules.";
    };
  };

  config = lib.mkIf cfg.enable {
    # useGlobalPkgs => HM reuses the system pkgs, so the HM-only overlays (custom
    # vim plugins, LSP servers, claude-code) must be present on the system set.
    nixpkgs.overlays = overlays.unstable.hmIntegrationOverlays;

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
        inherit (cfg) entry perHost desktop;
        standalone = false;
      };
    };
  };
}
