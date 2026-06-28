# Quickshell shell wiring. Installs the binary (with Qt5Compat.GraphicalEffects,
# the one QML module nixpkgs' quickshell omits) and, for the Phase 2 port,
# symlinks ~/.config/quickshell to the in-repo working copy so QML hot-reloads
# on save. The baked (read-only) install is deferred to the port plan's final
# task (spec 2g).
{
  config,
  lib,
  pkgs,
  ...
}: let
  # The in-repo helper scripts (task-bar/lib/*.sh) shell out to these at runtime.
  # They're all present in an interactive session, but pin them onto quickshell's
  # PATH so the shell works regardless of how it's launched (mirrors the rofi-bt
  # wrapper in rofi.nix). Used by btinfo.sh and audioctl.sh:
  #   bluetoothctl (bluez), pbpctrl, pw-dump / pw-metadata (pipewire),
  #   wpctl (wireplumber), pactl (pulseaudio), python3, plus coreutils/grep/sed/awk.
  runtimeDeps = [
    pkgs.bash
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    pkgs.bluez # bluetoothctl
    pkgs.pipewire # pw-dump
    pkgs.wireplumber # wpctl
    pkgs.pulseaudio # pactl
    pkgs.python3
    pkgs.systemd # busctl (mpris-extra.sh)
    pkgs.pbpctrl # Pixel Buds control (btinfo.sh pbp/set)
  ];

  quickshell' = pkgs.quickshell.overrideAttrs (o: {
    buildInputs = (o.buildInputs or []) ++ [pkgs.qt6.qt5compat];
    # wrapQtAppsHook applies these when wrapping bin/qs and bin/quickshell, so the
    # shell's child processes (bash -lc lib/*.sh) inherit the deps on PATH.
    qtWrapperArgs =
      (o.qtWrapperArgs or [])
      ++ ["--prefix PATH : ${lib.makeBinPath runtimeDeps}"];
  });
in {
  home.packages = [quickshell'];

  # DEV: live-editable config tree. Hardcoded thanatos repo path on purpose --
  # this is temporary; the port plan's 2g task replaces it with a baked install.
  xdg.configFile."quickshell".source =
    config.lib.file.mkOutOfStoreSymlink "/home/michael/nix-config/features/hm/wayland/quickshell";
}
