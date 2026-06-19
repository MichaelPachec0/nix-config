# Hyprland compositor configuration.
#
# Keybinds come from ./common.nix via the generatedHyprBinds module arg
# (the shared sway keybindings translated through toHypr).
{
  config,
  lib,
  pkgs,
  generatedHyprBinds,
  waybarLaunch,
  ...
}: let
  firefox = "${lib.getExe config.programs.firefox.package}";
in {
  config = {
    wayland = {
      windowManager.hyprland = {
        enable = true;
        package = pkgs.latest.hyprland;
        # package = pkgs.emptyDirectory;

        # hy3: i3/sway-style manual tiling with tabbed nodes. Built against the
        # same Hyprland input as pkgs.latest.hyprland (helpers/overlays.nix), so
        # the plugin ABI always matches the running compositor.
        plugins = [pkgs.latest.hy3];
        systemd = {
          enable = false;
        };
        xwayland = {
          enable = true;
        };
        settings = {
          "$mod" = "SUPER";
          "$mainMod" = "SUPER";
          # "$terminal" = "kitty";
          "$menu" = "rofi -show combi -combi-modes 'window,drun'";

          "$HYPR_SCRIPTS" = "~/.config/hypr/scripts";
          bind =
            generatedHyprBinds
            ++ [
              # hy3 tabbed/grouped-node binds. These have no sway equivalent, so
              # they are appended here rather than generated from common.nix.
              # (Directional focus/move, splits and layout toggles ARE generated
              # via toHypr -> hy3:* dispatchers; see common.nix.)

              # Toggle the focused group between a tab stack and a plain split.
              "SUPER, g, hy3:changegroup, toggletab"

              # Cycle tabs within the focused tab group (wraps around).
              "SUPER, bracketright, hy3:focustab, r, wrap"
              "SUPER, bracketleft,  hy3:focustab, l, wrap"

              # Expand the focused node over its siblings; Shift+e resets it.
              "SUPER, e, hy3:expand, expand"
              "SUPER Shift, e, hy3:expand, base"

              # Re-balance every split on the workspace back to equal. The
              # `workspace` arg is required: hy3 0.55's group-scope equalize
              # (no arg) only resets the parent node's own ratio, not its
              # children, so it is a no-op for two side-by-side windows.
              "SUPER Shift, equal, hy3:equalize, workspace"
            ];

          env = [
            "AQ_NO_MODIFIERS,1"
            "XDG_CURRENT_DESKTOP,Hyprland"
            "XDG_SESSION_DESKTOP,Hyprland"
            "XDG_SESSION_TYPE,wayland"
            "NIXOS_OZONE_WL,1"
            "MOZ_ENABLE_WAYLAND,1"
            "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
            "EDITOR,vim"
            "_JAVA_AWT_WM_NONREPARENTING,1"
            "QT_AUTO_SCREEN_SCALE_FACTOR,1"
            "QT_ENABLE_HIGHDPI_SCALING,1"
            "SDL_VIDEO_DRIVER,wayland"
            "XCURSOR_SIZE,24"
            "QT_FONT_DPI,96"

            "GDK_BACKEND,wayland,x11"
            "QT_QPA_PLATFORM,wayland;xcb"
            "SDL_VIDEODRIVER,wayland"
            "CLUTTER_BACKEND,wayland"

            "TERMINAL,kitty"
          ];
          input = {
            # ~200ms delay (mac InitialKeyRepeat 15), rate 45Hz.
            repeat_rate = 45;
            repeat_delay = 200;

            # accel_profile is global in Hyprland (no per-touchpad scope
            # like sway's type:touchpad). "adaptive" is the libinput
            # default, so the mouse is unaffected; this just mirrors sway.
            accel_profile = "adaptive";

            # Touchpad parity with sway's type:touchpad block.
            touchpad = {
              natural_scroll = true; # sway natural_scroll enabled
              disable_while_typing = true; # sway dwt enabled
              "tap-to-click" = true; # sway tap enabled
              drag_lock = false; # sway drag_lock disabled
            };
          };

          # Per-device override -- parity with sway's PS4 controller
          # touchpad rule (1356:2508 Sony ... Wireless Controller Touchpad).
          # Hyprland matches by the lowercased, hyphenated libinput name;
          # verify with `hyprctl devices` when the controller is connected
          # (a wrong name is a harmless no-op).
          device = [
            {
              name = "sony-interactive-entertainment-wireless-controller-touchpad";
              disable_while_typing = false; # sway dwt disabled
              "tap-to-click" = true; # sway tap enabled
            }
          ];
          # 3-finger horizontal swipe to switch workspaces (replaces sway's
          # `bindgesture swipe:left/right`). Uses the 0.49+ `gesture` keyword;
          # the old `gestures { workspace_swipe }` category was removed in 0.55.
          gesture = [
            "3, horizontal, workspace"
          ];
          group = {
            #This variable sets the color of the active window`s border in a group
            "col.border_active" = "rgba(5eead4ee)";

            #This subgroup contains variables to set the colors of the "bar"
            groupbar = {
              "col.inactive" = "rgba(595959aa)";
              "col.active" = "rgba(595959FF)";
            };
          };

          # hy3 plugin config: tab-bar look + autotiling for tabbed nodes.
          plugin.hy3 = {
            tabs = {
              height = 22;
              padding = 6;
              render_text = true;
              text_center = true;
            };
            # autotile: new windows split the focused node along its longer
            # axis automatically (i3-like), so manual splith/splitv is optional.
            autotile = {
              enable = true;
              ephemeral_groups = true;
            };
          };

          # Resize submap lives in extraConfig below: submaps are
          # order-sensitive and can't be expressed via `settings`.
          render = {
            cm_enabled = true;
            cm_auto_hdr = 1;
            cm_sdr_eotf = 0;
          };
          general = {
            layout = "hy3";
            gaps_in = 3;
            gaps_out = 6;
            border_size = 3;
            resize_on_border = false;
            allow_tearing = false;

            "col.active_border" = "rgba(87b158bf)";
            "col.inactive_border" = "rgba(595959aa)";
          };

          decoration = {
            rounding = 10;
            active_opacity = 1.0;
            inactive_opacity = 1.0;
            dim_inactive = false;
            dim_strength = 0.19;
            dim_around = 0.6;

            blur = {
              enabled = true;
              size = 5;
              # Heavy blur (4 passes + xray) only on strong-GPU hosts (thanatos);
              # every other device falls back to a lighter 3-pass, no-xray blur.
              passes =
                if config.gpu.strong.enable
                then 4
                else 3;
              new_optimizations = true;
              xray = config.gpu.strong.enable;
              popups = true;
            };

            shadow = {
              enabled = false;
              range = 4;
              render_power = 3;
              color = "rgba(00220044)";
            };
          };
          monitor = [
            "desc:LG Display 0x0676,1920x1080@60.02,6400x0,1.0"
            "desc:Shenzhen KTC Technology Group H27S17 0x00000001,2560x1440@119.99,3840x0,1.0,bitdepth,10"
            "desc:ASUSTek COMPUTER INC VG279 K5LMQS018158,1920x1080@119.98,0x0,1.0,bitdepth,10"
            "desc:ASUSTek COMPUTER INC VG259QM S1LMQS002054,1920x1080@119.88,1920x0,1.0,bitdepth,10"
            " , preferred, auto, 1"
          ];
          animations = {
            enabled = true;

            bezier = [
              "easeOutQuint,0.22,1,0.36,1"
              "easeInQuart,0.89,0.03,0.68,0.19"
              "softLinear,0.1,0.1,1,1"
            ];

            animation = [
              "windows,1,3,easeOutQuint,popin 90%"
              "windowsIn,1,3,easeOutQuint,popin 90%"
              "windowsOut,1,2,easeInQuart,popin 95%"
              "windowsMove,1,3,easeOutQuint,slide"
              "fade,1,3,softLinear"
              "workspaces,1,4,easeOutQuint,slidefade 20%"
            ];
          };
          exec-once = [
            waybarLaunch
            # sworkstyle auto-detects sway vs hyprland, so the bare PATH call
            # works the same as the sway session (see ./sway.nix).
            "sworkstyle >/tmp/sworkstyle.log 2>&1"
            "${lib.getExe pkgs.activate-linux} -t \"Activate NixOS\" -m \"Edit configuration.nix to activate NixOS.\" -x 360 -c \"1-1-1-0.10\""
            # Per-workspace app autostarts (sway uses mkWorkspace + swaymsg;
            # hyprland assigns each window with the [workspace N silent] prefix,
            # which needs no sleep/stagger).
            "[workspace 1 silent] kitty"
            "[workspace 2 silent] ${firefox}"
            "[workspace 3 silent] ${firefox} --private-window google.com"
            "[workspace 3 silent] legcord"
            "[workspace 3 silent] keepassxc"
            "[workspace 3 silent] telegram"
            # "${lib.getExe pkgs.hyprshade} on ${./shaders/main.glsl}"
          ];
        };
        systemd.variables = ["--all"];

        # Resize submap -- parity with sway's `resize` mode. common.nix's
        # toHypr maps Super+r to `submap, resize`; this defines that submap.
        # vim hjkl resizes, Shift+hjkl nudges (floating only, like sway),
        # plain `r` equalizes the focused split, and Escape / Return /
        # Super+r exit. Submaps are order-sensitive, so they live in
        # extraConfig (appended after the global binds) rather than in
        # `settings`.
        extraConfig = ''
          submap = resize
          binde = , h, resizeactive, -10 0
          binde = , l, resizeactive, 10 0
          binde = , k, resizeactive, 0 -10
          binde = , j, resizeactive, 0 10
          binde = SHIFT, h, moveactive, -10 0
          binde = SHIFT, l, moveactive, 10 0
          binde = SHIFT, k, moveactive, 0 -10
          binde = SHIFT, j, moveactive, 0 10
          # `r` equalizes every split on the workspace back to 50/50. Under
          # the hy3 layout `layoutmsg splitratio` does nothing (it drives
          # Hyprland's built-in layouts, not hy3's tree), so use hy3's own
          # equalize. The `workspace` arg is required: hy3 0.55's group-scope
          # equalize (no arg) only resets the parent node's own ratio, not
          # its children -- a no-op for two side-by-side windows.
          bind = , r, hy3:equalize, workspace
          bind = , escape, submap, reset
          bind = , return, submap, reset
          bind = SUPER, r, submap, reset
          submap = reset
        '';
      };
    };
  };
}
