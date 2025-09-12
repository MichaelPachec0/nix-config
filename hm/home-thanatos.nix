{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: let
in {
  # thanatos has a discrete GPU -- opt into the heavier visual effects (full blur).
  gpu.strong.enable = true;

  wayland.windowManager.sway = let
      extraSessionCommands = ''

        # Needed
        export XDG_CURRENT_DESKTOP="sway";
        export WLR_DRM_NO_MODIFIERS="1";
        # export WLR_DRM_NO_ATOMIC="1";
        export NIXOS_OZONE_WL="1";

        export XDG_SESSION_TYPE="wayland";
        export QT_QPA_PLATFORM="wayland";
        # have sway handle decoration
        export QT_WAYLAND_DISABLE_WINDOWDECORATION="1";
        export _JAVA_AWT_WM_NONREPARENTING="1";

        # QT stuff technically optional unless hiDPI
        export QT_AUTO_SCREEN_SCALE_FACTOR=1;
        export QT_ENABLE_HIGHDPI_SCALING=1;
        # export QT_QPA_PLATFORM="wayland;xcb";
        # export QT_QPA_PLATFORMTHEME="gnome";

        # XDG_CURRENT_DESKTOP="sway:GNOME:Unity:"
        XDG_CURRENT_DESKTOP="sway:gnome"
        # NOTE: this is optional, want to run vulkan
        # not using for now
        # export WLR_RENDERER="vulkan,gles2";

        # MOZ env, optional
        export MOZ_ENABLE_WAYLAND="1";
        export MOZ_DBUS_REMOTE="1";

        # GTK stuff
        export GTK_USE_PORTAL="1"

        # SDL
        # export SDL_VIDEODRIVER="wayland,x11,kmsdrm,windows,directx";
        # export SDL_VIDEO_DRIVER="wayland,x11,kmsdrm,windows";
        export SDL_VIDEODRIVER="wayland";
        export SDL_VIDEO_DRIVER="wayland";

        # Display stuff
        export XCURSOR_SIZE=24
        export QT_FONT_DPI=96

        # electron
        export ELECTRON_OZONE_PLATFORM_HINT="auto";

        export CLUTTER_BACKEND="wayland";

        export ANKI_WAYLAND="1";
        export WLR_BACKEND="vulkan";
        # export MESA_LOADER_DRIVER_OVERRIDE=zink;

        # Let sway have access to your nix profile
        # source "${pkgs.nix}/etc/profile.d/nix.sh"
      '';
      sway = pkgs.nw.swayfx.override {inherit extraSessionCommands;};
  in  {
    package = lib.mkForce sway;
    config = {
      output.eDP-1.scale = lib.mkForce "1.0";
      input = lib.mkForce {
        "input \"2:10:TPPS/2_Elan_TrackPoint\"" = {
          accel_profile = "flat";
          pointer_accel = "-0.3";
        };
        "2:7:SynPS/2_Synaptics_TouchPad" = {
          dwt = "enabled";
          dwtp = "enabled";
          drag_lock = "disabled";
          # tap enabled
          tap = "enabled";
          accel_profile = "flat";
          pointer_accel = "0.4";
          natural_scroll = "enabled";
        };
      };
    };
  };
  programs.kitty.font.size = lib.mkForce 7.3;
}
