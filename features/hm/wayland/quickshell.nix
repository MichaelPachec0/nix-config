# Quickshell shell wiring. Installs the binary (with Qt5Compat.GraphicalEffects,
# the one QML module nixpkgs' quickshell omits) and, for the Phase 2 port,
# symlinks ~/.config/quickshell to the in-repo working copy so QML hot-reloads
# on save. The baked (read-only) install is deferred to the port plan's final
# task (spec 2g).
{
  config,
  pkgs,
  ...
}: let
  quickshell' = pkgs.quickshell.overrideAttrs (o: {
    buildInputs = (o.buildInputs or []) ++ [pkgs.qt6.qt5compat];
  });
in {
  home.packages = [quickshell'];

  # DEV: live-editable config tree. Hardcoded thanatos repo path on purpose --
  # this is temporary; the port plan's 2g task replaces it with a baked install.
  xdg.configFile."quickshell".source =
    config.lib.file.mkOutOfStoreSymlink "/home/michael/nix-config/features/hm/wayland/quickshell";
}
