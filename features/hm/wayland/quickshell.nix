# Quickshell shell wiring. Installs the binary and, for the Phase 2 port,
# symlinks ~/.config/quickshell to the in-repo working copy so QML hot-reloads
# on save. The baked (read-only) install is deferred to the port plan's final
# task (spec 2g). Qt5Compat.GraphicalEffects and the helper scripts' runtime
# PATH are added by the top-level `quickshell` override in helpers/overlays.nix,
# so every consumer of the package gets them, not just this module.
{
  config,
  pkgs,
  ...
}: let
  # Toggle the bar look at runtime: `bar-style ghost` / `bar-style frosted`.
  # Writes a state file OUTSIDE ~/.config/quickshell (the repo symlink) that the
  # BarStyle singleton's FileView watches, so the bar hot-swaps with no reload.
  barStyleCmd = pkgs.writeShellApplication {
    name = "bar-style";
    text = ''
      style="''${1:-}"
      case "$style" in
        ghost | frosted | ghost-glass) ;;
        *)
          echo "usage: bar-style <ghost|frosted|ghost-glass>" >&2
          exit 1
          ;;
      esac
      dir="''${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
      mkdir -p "$dir"
      printf '%s\n' "$style" >"$dir/bar-style"
    '';
  };
  # Toggle the raised-glyph halo at runtime: `bar-glow off` / `bar-glow on`.
  # Same state-file mechanism as bar-style. Worth having as a lever rather than
  # a source constant: BarText.qml/BarStyle.qml are files Quickshell's hot reload
  # does NOT pick up, so changing the halo in source means a full bar restart,
  # whereas this is a live property change.
  barGlowCmd = pkgs.writeShellApplication {
    name = "bar-glow";
    text = ''
      state="''${1:-}"
      case "$state" in
        on | off) ;;
        *)
          echo "usage: bar-glow <on|off>" >&2
          exit 1
          ;;
      esac
      dir="''${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
      mkdir -p "$dir"
      printf '%s\n' "$state" >"$dir/bar-glow"
    '';
  };
in {
  home.packages = [
    pkgs.quickshell
    barStyleCmd
    barGlowCmd
  ];

  # DEV: live-editable config tree. Hardcoded thanatos repo path on purpose --
  # this is temporary; the port plan's 2g task replaces it with a baked install.
  xdg.configFile."quickshell".source =
    config.lib.file.mkOutOfStoreSymlink "/home/michael/nix-config/features/hm/wayland/quickshell";
}
