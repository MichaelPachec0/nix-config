# Sway (swayfx) compositor configuration.
#
# Keybinds come from ./common.nix via the generatedSwayBinds module arg.
{
  config,
  options,
  lib,
  pkgs,
  generatedSwayBinds,
  waybarLaunch,
  ...
}: {
  config = {
    wayland.windowManager.sway = let
      # package = pkgs.sway;
      # NOTE: this might be needed whene the changes to sway (removing wl-drm for dmabuf) happen.
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
        # export MESA_LOADER_DRIVER_OVERRIDE=zink;

        # Let sway have access to your nix profile
        # source "${pkgs.nix}/etc/profile.d/nix.sh"
      '';
      sway = pkgs.nw.swayfx.override {inherit extraSessionCommands;};
    in {
      # inherit extraSessionCommands;

      enable = true;
      # WARN: this is dangerous, keep checking when this is fixed
      checkConfig = false;

      package = sway;
      systemd = {
        enable = false;
        dbusImplementation = "broker";
        variables =
          options.wayland.windowManager.sway.systemd.variables.default
          ++ [
            "I3SOCK"
            "PATH"
            "XDG_RUNTIME_DIR"
            "XDG_DATA_DIRS"
            "DBUS_SESSION_BUS_ADDRESS"
            "XCURSOR_PATH"
          ];
        xdgAutostart = true;
      };

      config = let
        modifier = "Mod4";
        mod = modifier;
      in rec {
        inherit modifier;

        terminal = "kitty";
        # menu = "wofi --show drun";

        menu = "rofi -show combi -combi-modes 'window,drun'";

        input = {
          "type:keyboard" = {
            repeat_rate = "45";
            repeat_delay = "200";
          };
          "type:touchpad" = {
            natural_scroll = "enabled";
            # pointer_accel = "1";
            accel_profile = "adaptive";
            # NOTE: disable while typing.
            dwt = "enabled";
            tap = "enabled";
            drag_lock = "disabled";
          };

          # NOTE: ps4 touchpad
          "1356:2508:Sony_Interactive_Entertainment_Wireless_Controller_Touchpad" = {
            dwt = "disabled";
            tap = "enabled";
          };
        };

        floating.criteria = [
          # NOTE: firefox related floating rules.
          {
            title = "Firefox.* — Sharing Indicator";
          }
          {
            # app_id = "firefox";
            title = "Picture-in-Picture";
          }
          {title = "(Dropdown)";}
          {title = "^About Mozilla Firefox$";}
          # WARN: Do not use this, it screws up initial window creation.
          # {
          #   # NOTE: armcord right click shows nothing for this.
          #   app_id = "";
          # }
          # NOTE: this will work with the applet + toggle window.
          {class = "^KeePassXC$";}

          {class = "^Mpv$";}
          {class = "Pavucontrol";}
          {app_id = "launcher";}
          {app_id = ".*force_float.*";}
          {app_id = "^nm-connection-editor$";}
          {title = "^Complete Installation$";}
          {title = "^Steam - News (.* of .*)$";}
          {title = "^Steam - Update";}
          {title = "^Steam - Self Updater$";}
          {title = "^Steam Guard - Computer Authorization Required$";}
          {title = "^zoom$";}
          # NOTE: this catches about pages on websites, need to fix
          # {title = "About";}

          # Generic indicators that windows do not want to be tiled.
          {class = "Ibus-ui-gtk3";}
          {window_role = "pop-up";}
          {window_role = "bubble";}
          {window_role = "task_dialog";}
          {window_role = "Preferences";}
          {window_type = "dialog";}
          {window_type = "menu";}
          {class = "Pinentry";}
          {window_type = "dialog";}
          {app_id = "^pavucontrol$";}
          {app_id = "zenity";}
          {app_id = "floating_update";}
          # child anki windows.
          {
            class = "Anki";
            title = "Profiles";
          }
          {
            class = "Anki";
            title = "Add";
          }
          {
            class = "Anki";
            title = "^Browse.*";
          }
        ];
        window.commands = [
          {
            # NOTE: ignore sharing window.
            criteria = {
              "title" = "Firefox.* — Sharing Indicator";
            };
            command = "nofocus";
          }
        ];
        keybindings = generatedSwayBinds;
        # WARN: i3 status gets screwy with applet context menus. Use waybar instead.
        # TODO: Asthetic configuration of waybar.
        bars = [];
        # bars = [{command = "waybar";}];
        # bars = [
        #   {
        #     mode = "dock";
        #     hiddenState = "hide";
        #     position = "bottom";
        #     workspaceButtons = true;
        #     workspaceNumbers = true;
        #     # statusCommand = "${pkgs.i3status}/bin/i3status";
        #     statusCommand = "${lib.getExe cfg.programs.i3status-rust.package} ~/.config/i3status-rust/config-bottom.toml";
        #
        #     fonts = {
        #       names = ["monospace"];
        #       size = 10.0;
        #     };
        #     trayOutput = "*";
        #     colors = {
        #       background = "#000001";
        #       statusline = "#ffffff";
        #       separator = "#666666";
        #       focusedWorkspace = {
        #         border = "#4c7899";
        #         background = "#285577";
        #         text = "#ffffff";
        #       };
        #       activeWorkspace = {
        #         border = "#333333";
        #         background = "#5f676a";
        #         text = "#ffffff";
        #       };
        #       inactiveWorkspace = {
        #         border = "#333333";
        #         background = "#222222";
        #         text = "#888888";
        #       };
        #       urgentWorkspace = {
        #         border = "#2f343a";
        #         background = "#900000";
        #         text = "#ffffff";
        #       };
        #       bindingMode = {
        #         border = "#2f343a";
        #         background = "#900000";
        #         text = "#ffffff";
        #       };
        #     };
        #   }
        # ];

        # TODO: this whole path
        modes = {
          resize = let
            # pxCount = "10 px or 2 ppt";
            pxCount = "10 px";
            cfg = config.wayland.windowManager.sway;
          in {
            "${cfg.config.left}" = "resize shrink width ${pxCount}";
            "${cfg.config.down}" = "resize grow height ${pxCount}";
            "${cfg.config.up}" = "resize shrink height ${pxCount}";
            "${cfg.config.right}" = "resize grow width ${pxCount}";
            # bindsym Up move up 192 px
            # bindsym Left move left 192 px
            # bindsym Down move down 192 px
            # bindsym Right move right 192 px

            "Shift+${cfg.config.left}" = "move left 10 px";
            "Shift+${cfg.config.down}" = "move down 10 px";
            "Shift+${cfg.config.up}" = "move up 10 px";
            "Shift+${cfg.config.right}" = "move right 10 px";
            "Escape" = "mode default";
            "Return" = "mode default";
            "${mod}+r" = "mode default";
          };
        };
        output = {
          eDP-1 = {
            # becomes 15' @ 1440p
            scale = "1.5";
          };
        };
      };
      extraConfigEarly = ''
        blur enable
        blur_xray disable
        blur_passes 3
        blur_radius 2

        layer_effects "waybar" {
            blur enable;
            blur_xray disable;
            blur_ignore_transparent disable;
            shadows disable;
            # corner_radius 20;
        }

        default_border pixel 2
        gaps inner 4
        gaps outer 4

        # Opacity
        for_window [class=".*"] opacity set 0.9
        for_window [app_id="gimp*"] opacity set 1.0
        for_window [app_id="krita*"] opacity set 1.0
        for_window [app_id="org.inkscape.Inkscape"] opacity set 1.0
        for_window [app_id="virt-manager"] opacity set 1.0
        for_window [app_id="com.obsproject.Studio"] opacity set 1.0

        # Blur
        for_window [app_id="gimp*"] blur disable
        for_window [class="krita*"] blur disable
        for_window [app_id="org.inkscape.Inkscape"] blur disable
        for_window [app_id="virt-manager"] blur disable
        for_window [app_id="com.obsproject.Studio"] blur disable
      '';

      # WARN: this is only applied when the package is not null.
      extraConfig = let
        # TODO: better way of doing this?
        firefox = "${lib.getExe config.programs.firefox.package}";
        # NOTE: Tries and gets the entry point for spotify, spotifywm -> spotify theme/spotify
        # found out using the repl (builtins.elemAt homeConfigurations.michael-nyx.config.programs.spicetify.createdPackages 0)
        # exec sleep 2 && swaymsg "workspace number 2; exec
        # exec sleep 10 &&  swaymsg "workspace number 9; exec keepassxc; ${spotify}"
        # mkWorkspace = wkNumber: sleepNumber: allApps: let
        mkWorkspace = wkNumber: allApps: let
          appCommand = builtins.concatStringsSep "; " allApps;
          # sleep = builtins.toString sleepNumber;
          sleep = builtins.toString ((wkNumber * 2) + 1);
          wk = builtins.toString wkNumber;
        in ''exec sleep ${sleep} && swaymsg "workspace number ${wk}; exec ${appCommand}"'';
        fastanime-notifier = pkgs.writeShellScriptBin "fa-notifier" ''
          # Check if the process `fastanime .* notifier` is running
          if ! ps aux | grep -q '[f]astanime .* notifier'; then
            echo "Initializing fastanime anilist notifier"
            # Start the notifier process in the background, suppressing output
            nohup fastanime --log-file anilist notifier >/dev/null 2>&1 &
          fi
        '';
        extraExtraConfig = ''
          ## SWAYFX CONFIG
          corner_radius 14
          shadows on
          shadow_offset 0 0
          shadow_blur_radius 20
          shadow_color #000000BB
          shadow_inactive_color #000000B0

          default_dim_inactive 0.2

          layer_effects "notif" blur enable; shadows enable; corner_radius 20
          layer_effects "osd" blur enable; shadows enable; corner_radius 20
          layer_effects "work"  shadows enable
          layer_effects "panel" shadows enable
          layer_effects "calendarbox"shadows enable; corner_radius 12
          layer_effects "rofi" {
            blur enable
            corner_radius 15
            shadows enable
          }
          layer_effects "wofi" {
              blur enable;
              blur_xray disable;
              corner_radius 18;
          }


          # window colors
          #                       border              background         text                 indicator
          client.focused          $bg-color           $bg-color          $text-color          $bg-color
          client.unfocused        $inactive-bg-color $inactive-bg-color $inactive-text-color  $inactive-bg-color
          client.focused_inactive $inactive-bg-color $inactive-bg-color $inactive-text-color  $inactive-bg-color
          client.urgent           $urgent-bg-color    $urgent-bg-color   $text-color          $urgent-bg-color

          titlebar_separator enable
          titlebar_padding 16
          title_align center
          default_border normal 2
          default_floating_border normal 2
        '';
      in ''
        # NOTE: This lets nixos know that we prefer to use wayland for electron
        # apps.
        # https://github.com/swaywm/sway/wiki#gtk-applications-take-20-seconds-to-start
        # For flatpak to be able to use PATH programs
        # exec systemctl --user restart xdg-desktop-portal.service
        # exec_always systemctl --user import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_RUNTIME_DIR XDG_DATA_DIRS DBUS_SESSION_BUS_ADDRESS
        # exec_always "${lib.getExe pkgs.waybar} > ~/.cache/waybar-$(date +%F-%T).log 2>&1"
        exec "${waybarLaunch}"


        # QT_QPA_PLATFORMTHEME="gtk2"
        # QT_STYLE_OVERRIDE="adwaita-dark"



        # Make sure that hyrpland is stopped.
        # these should not be an issue anymore.
        # exec systemctl stop --user hyprland-session.target
        # exec systemctl stop --user xdg-desktop-portal-hyprland.service

        # Make sure that shikane is enabled.
        exec systemctl enable --user shikane@sway.service
        # make sure we start swayidle.
        exec systemctl start --user swayidle.service
        # exec echo $PATH > ~/tmp/path.log
        # exec export SIGNAL_USE_WAYLAND="1"

        # Allow switching between workspaces with left and right swipes
        bindgesture swipe:right workspace prev
        bindgesture swipe:left workspace next

        # TON of terrible done config
        # TODO: REDO THIS WHOLE THING!
        # NOTE: 1-3 laptop, 4-6 main monitor, 6-9 ancillary monitor
        # every output has a terminal, browser and special app
        # terminal for laptop monitor
        ${mkWorkspace 1 ["kitty"]}
        ${mkWorkspace 2 ["${firefox}"]}
        # Half firefox windows (regular and private)
        # ${mkWorkspace 3 ["${firefox}" "${firefox}"]}
        # switch this to legcord
        ${mkWorkspace 3 ["${firefox} --private-window google.com" "legcord" "keepassxc" "telegram"]}

        exec sworkstyle &> /tmp/sworkstyle.log
        # exec_always ${lib.getExe fastanime-notifier}
        # do this differently
        exec ${lib.getExe pkgs.activate-linux} -t "Activate NixOS" -m "Edit configuration.nix to activate NixOS." -x 360 -c "1-1-1-0.10"
      '';

      # ${mkWorkspace 9 [
      #    "${lib.getExe pkgs.keepassxc}"
      #   "gtk-launch spotify"
      # ]}
      # # "gtk-launch spotify &>/tmp/\$(date +%Y-%m-%dT%H:%M:%S%:z)-spotify.log"
      # exec systemctl start --user swayidle

      # Once everything is setup then run shikane.
      wrapperFeatures = {
        base = false;
        gtk = true;
      };
      # systemd = {
      #   xdgAutostart = true;
      # };
    };
  };
}
