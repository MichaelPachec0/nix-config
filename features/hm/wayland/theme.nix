# Theme seam: the single source of truth for the desktop's palette + fonts.
# Every build-time config (Hyprland, later rofi/kitty/GTK/hyprlock) reads from
# `_module.args.theme`; the same data is emitted to ~/.config/theme/colors.json
# for the runtime Quickshell ThemeEngine (Phase 2). v1 ships Gruvbox-dark only;
# adding a theme later means adding a branch here, not editing every module.
#
# This module owns font NAME tokens only. The font binaries are installed
# system-wide via NixOS `fonts.packages` (nixos/nyx/configuration.nix), the
# repo's font mechanism -- home.packages fonts are not on the system fontconfig
# path here. Manrope is vendored there (nixpkgs dropped pkgs.manrope);
# JetBrainsMono (mono/icon/terminal) already ships in that set.
{...}: let
  # Gruvbox-dark-hard. Bare 6-hex (no '#', no alpha) so consumers can format:
  # Hyprland uses "rgba(<hex><AA>)", JSON/QML use "#<hex>".
  palette = {
    bgMain = "1d2021"; # bg0_hard (darkest)
    bgCard = "282828"; # bg0
    bgItem = "3c3836"; # bg1 (raised item / inactive tab)
    bgItemHover = "504945"; # bg2
    textPrimary = "ebdbb2"; # fg1
    textSecondary = "a89984"; # fg4 (muted)
    textOnAccent = "1d2021"; # dark text on accent fills
    accent = "87b158"; # primary green (current active-border; swap here for a
    # canonical gruvbox green like 8ec07c/b8bb26 if desired)
    accentBlue = "83a598"; # gruvbox blue
    accentRed = "fb4934"; # gruvbox bright red (urgent/critical)
    accentOrange = "fe8019"; # gruvbox orange
    accentSlider = "8ec07c"; # gruvbox aqua (secondary green)
    borderInactive = "595959"; # inactive window border grey (kept identical)
  };

  fonts = {
    ui = "Manrope"; # all UI chrome
    mono = "JetBrainsMono Nerd Font"; # icons + general mono
    icon = "JetBrainsMono Nerd Font";
    terminal = "JetBrainsMono Nerd Font Mono"; # consumed by kitty in a later phase
    lock = "Manrope";
  };

  meta = {
    name = "gruvbox";
    mode = "dark";
  };

  # colors.json: '#'-prefixed for QML, plus fonts + mode.
  colorsJson = builtins.toJSON {
    mode = "${meta.name}-${meta.mode}";
    colors = builtins.mapAttrs (_: v: "#${v}") palette;
    inherit fonts;
  };
in {
  _module.args.theme = {inherit palette fonts meta;};

  xdg.configFile."theme/colors.json".text = colorsJson;
}
