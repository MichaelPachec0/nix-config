{
  lib,
  # true standalone; false when integrated as a NixOS module (useGlobalPkgs).
  standalone ? true,
  ...
}: {
  imports = [./programs.nix ./services.nix];
  options = {
    graphical.enable =
      lib.mkEnableOption "Enable graphical programs common in all desktops";
    audio.enable =
      lib.mkEnableOption "Enable audio programs common in all desktops";
    report-changes.enable = lib.mkEnableOption "Create a report after sucessful home-manager generation";
    devMachine.enable =
      lib.mkEnableOption
      "Enables developer configuration. This includes certain packages as well as configuration.";
    gpu.strong.enable =
      lib.mkEnableOption
      "device has a strong/discrete GPU; enables heavier visual effects (e.g. full-quality Hyprland blur)";
  };
  # Shared across all home-manager entrypoints (home.nix, home-test.nix, sysadmin.nix),
  # all of which import this module. Only applied for standalone HM; when integrated
  # as a NixOS module (useGlobalPkgs) the system owns nixpkgs.config.
  config = lib.mkIf standalone {
    nixpkgs.config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };
  };
}
