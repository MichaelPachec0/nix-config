# ICD STUFF!
# https://github.com/swaywm/sway/issues/1486#issuecomment-2344740148
{
  config,
  options,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [./swayidle.nix ./waybar ./rofi.nix];
  config = let
    cfg = config;
    browser = "firefox";

        firefox = "${lib.getExe config.programs.firefox.package}";

  # Base variables

  mod = "Mod4";
  terminal = "kitty";
  menu = "rofi -show combi -combi-modes 'window,drun'";

  # Screenshot helper 

  Print = let
    f = "scrn-$(date +%Y-%m-%dT%H:%M:%S%:z).png";
  in ''
    exec grim -t png -g "$(slurp)" ~/Pictures/${f}
  '';

  # default keybindinds 

  swayKeybindings = {

    # Basics
    "${mod}+t" = "exec ${terminal}";
    "${mod}+q" = "kill";
    "${mod}+Shift+r" = "reload";

    "${mod}+shift+q" = ''
      exec swaynag -t warning -m 'Do you really want to exit sway?' -b 'Yes' 'swaymsg exit'
    '';

    # Focus (vim style)
    "${mod}+j" = "focus down";
    "${mod}+h" = "focus left";
    "${mod}+l" = "focus right";
    "${mod}+k" = "focus up";

    # Move containers
    "${mod}+Shift+j" = "move down";
    "${mod}+Shift+h" = "move left";
    "${mod}+Shift+l" = "move right";
    "${mod}+Shift+k" = "move up";

    # Workspaces
    "${mod}+1" = "workspace number 1";
    "${mod}+2" = "workspace number 2";
    "${mod}+3" = "workspace number 3";
    "${mod}+4" = "workspace number 4";
    "${mod}+5" = "workspace number 5";
    "${mod}+6" = "workspace number 6";
    "${mod}+7" = "workspace number 7";
    "${mod}+8" = "workspace number 8";
    "${mod}+9" = "workspace number 9";
    "${mod}+0" = "workspace number 10";

    "${mod}+SHIFT+1" = "move container to workspace number 1";
    "${mod}+SHIFT+2" = "move container to workspace number 2";
    "${mod}+SHIFT+3" = "move container to workspace number 3";
    "${mod}+SHIFT+4" = "move container to workspace number 4";
    "${mod}+SHIFT+5" = "move container to workspace number 5";
    "${mod}+SHIFT+6" = "move container to workspace number 6";
    "${mod}+SHIFT+7" = "move container to workspace number 7";
    "${mod}+SHIFT+8" = "move container to workspace number 8";
    "${mod}+SHIFT+9" = "move container to workspace number 9";
    "${mod}+SHIFT+0" = "move container to workspace number 10";

    # Layout
    "${mod}+b" = "splith";
    "${mod}+v" = "splitv";
    "${mod}+z" = "layout stacking";
    "${mod}+x" = "layout tabbed";
    "${mod}+c" = "layout toggle split";

    "${mod}+f" = "fullscreen toggle";
    "${mod}+a" = "focus parent";
    "${mod}+d" = "focus child";

    # Scratchpad
    "${mod}+Shift+minus" = "move scratchpad";
    "${mod}+minus" = "scratchpad show";

    "${mod}+r" = "mode 'resize'";

    # Apps
    "${mod}+w" = "exec ${firefox}";
    "${mod}+Shift+f" = "floating toggle";
    "${mod}+Space" = "exec ${menu}";

    inherit Print;
    "${mod}+p" = Print;

    "${mod}+alt+l" = "exec loginctl lock-session";

    # Media
    "XF86AudioRaiseVolume" = "exec volumectl -u up";
    "XF86AudioLowerVolume" = "exec volumectl -u down";
    "XF86AudioMute" = "exec volumectl toggle-mute";
    "XF86AudioMicMute" = "exec volumectl -m toggle-mute";
    "XF86AudioPlay" = "exec playerctl play-pause";

    "XF86MonBrightnessUp" = "exec brightnessctl -e s 2%+";
    "XF86MonBrightnessDown" = "exec brightnessctl -e s 2%-";

    "${mod}+n" =
      "exec ${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw";
  };

  # Translation Layer -> Hyprland

  # Hypr Translation

  # Direction mapping for Hypr
  dirMap = {
    "left"  = "l";
    "right" = "r";
    "up"    = "u";
    "down"  = "d";
  };

toHypr = combo: cmd:
  let
    # Split combo into parts (Mod4+Shift+1 -> [ "Mod4" "Shift" "1" ])
    parts = lib.splitString "+" combo;

    # Last element is the key
    key = lib.last parts;

    # Everything except last is modifiers
    modsRaw = lib.init parts;

    # Normalize modifiers for Hyprland
    normalizeMod = m:
      if m == "Mod4" then "SUPER"
      else if lib.toLower m == "shift" then "SHIFT"
      else if lib.toLower m == "alt" then "ALT"
      else if lib.toLower m == "control" then "CTRL"
      else m;

    mods =
      lib.concatStringsSep " "
        (map normalizeMod modsRaw);

    # actions

    action =
      if lib.hasPrefix "exec " cmd then
        "exec, ${lib.removePrefix "exec " cmd}"

      else if cmd == "kill" then
        "killactive"

      else if cmd == "reload" then
        "exec, hyprctl reload"

      else if lib.hasPrefix "focus " cmd then
        let dir = lib.removePrefix "focus " cmd;
        in "movefocus, ${dirMap.${dir} or dir}"

      else if lib.hasPrefix "workspace number " cmd then
        "workspace, ${lib.removePrefix "workspace number " cmd}"

      else if lib.hasPrefix "move container to workspace number " cmd then
        "movetoworkspace, ${lib.removePrefix "move container to workspace number " cmd}"

      # move container direction 
      else if lib.hasPrefix "move " cmd then 
        let dir = lib.removePrefix "move " cmd; 
        in "movewindow, ${dirMap.${dir} or dir}"

      else if cmd == "floating toggle" then
        "togglefloating"

      else if cmd == "fullscreen toggle" then
        "fullscreen"

      else if cmd == "scratchpad show" then
        "togglespecialworkspace, magic"

      else if cmd == "move scratchpad" then
        "movetoworkspace, special:magic"

      else if cmd == "splith" then
        "layoutmsg, orientationleft"

      else if cmd == "splitv" then
        "layoutmsg, orientationtop"

      else if cmd == "layout toggle split" then
        "layoutmsg, togglesplit"

      else if cmd == "layout stacking" then
        "layoutmsg, cyclenext"

      else if cmd == "layout tabbed" then
        "layoutmsg, cyclenext"

      else if cmd == "mode 'resize'" then
        "submap, resize"

      else
        "exec, ${cmd}";

  in
    "${mods}, ${key}, ${action}";

  hyprBinds =
    lib.mapAttrsToList toHypr swayKeybindings;
  in {
    wayland = {
      windowManager.hyprland = {
        enable = true;
        package = pkgs.latest.hyprland;
        # package = pkgs.emptyDirectory;
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

          "$HYPR_SCRIPTS"     = "~/.config/hypr/scripts";
          bind = hyprBinds ++ 
          [
            "SUPER, g, togglegroup"
            "SUPER, bracketleft, changegroupactive, b"
            "SUPER, bracketright, changegroupactive, f"
            "SUPER Shift, bracketleft, movegroupwindow, b"
            "SUPER Shift, bracketright, movegroupwindow, f"

            #Moving non-tabbed window inside tabbed group by direction
            "SUPER Shift Control, h, moveintogroup, l"
            "SUPER Shift Control, l, moveintogroup, r"
            "SUPER Shift Control, k, moveintogroup, u"
            "SUPER Shift Control, j, moveintogroup, d"

            #Moving tabbed window out from the group
            "SUPER Shift Alt, h, moveoutofgroup, l"
            "SUPER Shift Alt, l, moveoutofgroup, r"
            "SUPER Shift Alt, k, moveoutofgroup, u"
            "SUPER Shift Alt, j, moveoutofgroup, d"

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
          };
          group = {
              #This variable sets the color of the active window`s border in a group
               "col.border_active" = "rgba(5eead4ee)";

            #This subgroup contains variables to set the colors of the "bar"
               groupbar = {
                    "col.inactive" = "rgba(595959aa)";
                    "col.active" = "rgba(595959FF)";
               };
          };
          
#SHIFT is for more accurate size changing
#            bind=SUPER,R,submap,resize
#            submap=resize
#                unbind = ,down
#                binde = , right, resizeactive,  100 0
#                binde = , left,  resizeactive, -100 0
#                binde = , down,  resizeactive,  0 100
#                binde = , up,    resizeactive,  0 -100
#                binde = SHIFT, right, resizeactive,  10 0
#                binde = SHIFT, left,  resizeactive, -10 0
#                binde = SHIFT, down,  resizeactive,  0 10
#                binde = SHIFT, up,    resizeactive,  0 -10
#                bind = , escape,submap,reset 
#                bind = , return,submap,reset 
#            submap=reset
          render = {
            cm_enabled = true;
            cm_auto_hdr = 1;
            cm_sdr_eotf = 0;
          };
          general = {
            layout = "dwindle";
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
              passes = if config.gpu.strong.enable then 4 else 3;
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
          # "${lib.getExe pkgs.hyprshade} on ${./shaders/main.glsl}"

          ];
        };
        systemd.variables = ["--all"];
      };
    };
    home.sessionVariables = {
    };
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
        keybindings = swayKeybindings;
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
        waybarpkg = pkgs.writeShellApplication {
          name = "wb_keep";
          runtimeInputs = with pkgs; [waybar];
          text = ''
            until waybar; do
              echo "Waybar is dead: exit code ''$?, long live waybar!" >&2
              sleep .5
            done
          '';
        };
        waybar-killer = pkgs.writeShellApplication {
          name = "wb_killer";
          text = ''
            {
              pkill wb_keep
              sleep .5
              pkill waybar
              sleep .5
            } || true
          '';
        };
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
        exec "${lib.getExe waybar-killer} && ${lib.getExe waybarpkg}"


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
    # NOTE: Not using this currently, as per the above bug where context menus
    # act like regular windows.
    programs.i3status-rust = {
      enable = false;
      bars = {
        bottom = {
          blocks = [
            {
              block = "disk_space";
              path = "/";
              info_type = "available";
              interval = 60;
              warning = 20.0;
              alert = 10.0;
            }
            {
              block = "memory";
              interval = 60;
              format = " $icon $mem_used_percents ";
              format_alt = " $icon $swap_used_percents ";
            }
            {
              block = "cpu";
              interval = 5;
              format = " $barchart $utilization $frequency ";
            }
            # {
            #   block = "load";
            #   interval = 5;
            #   format = " $icon $1m ";
            # }
            {
              block = "battery";
              device = "BAT0";
              interval = 10;
              format = " $icon $percentage $time $power ";
            }
            {block = "sound";}
            {
              block = "net";
              format = " $icon $ssid $signal_strength $ip ↓$speed_down ↑$speed_up ";
              interval = 10;
              theme_overrides = {
                idle_bg = "#00223f";
              };
            }
            {
              block = "time";
              interval = 2;
              format = " $timestamp.datetime(f:'%a %d/%m %R:%S') ";
            }
          ];
          # settings = {
          #   theme = {
          #     theme = "gruvbox-dark";
          #     overrides = {
          #       idle_bg = "#123456";
          #       idle_fg = "#abcdef";
          #     };
          #   };
          # };
          icons = "material-nf";
          theme = "gruvbox-dark";
        };
      };
    };

    home.pointerCursor = {
      #name = "phinger-cursors";
      #package = pkgs.phinger-cursors;
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
      gtk.enable = true;
      x11 = {
        enable = true;
        defaultCursor = "Adwaita";
      };
    };
    gtk = {
      enable = true;
      cursorTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
        size = 24;
      };
      font = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
        size = 10;
      };

      gtk3.extraConfig = {
        gtk-cursor-theme-name = "Adwaita";
        gtk-cursor-theme-size = 24;
      };

      theme = {
        # name = "Adwaita-dark";
        # package = pkgs.flat-remix-gtk;
        # name = "Flat-Remix-GTK-Blue-Dark";
        name = "Gruvbox-Yellow-Dark";

        package = pkgs.gruvbox-gtk-theme.override {
          themeVariants = ["all"];
          tweakVariants = ["macos"];
          iconVariants = ["Dark"];
        };
      };
    };
    qt = {
      enable = true;
      platformTheme.name = "gtk";
      # style.package = with pkgs; [adwaita-qt adwaita-qt6];
      style.name = "Gruvbox-Yellow-Dark";
    };
    systemd.user.services = let
      # NOTE: for later reading:
      # https://pychao.com/2021/02/24/difference-between-partof-and-bindsto-in-a-systemd-unit/
      # NOTE: This makes sure that when both targets are stopped
      # then the service is also stopped.
      # Might redo this later.
      waylandChecker = pkgs.writeShellApplication {
        name = "waylandChecker.sh";
        text = ''
          hyprCheck=$(systemctl is-active --user --quiet hyprland-session.target)
          swayCheck=$(systemctl is-active --user --quiet sway-session.target)
          if [[ $hyprCheck  || $swayCheck ]]; then
            exit 0
          else
            systemctl stop --user shikane.service
          fi
        '';
      };
      # NOTE: THIS MIGHT BE WRONG. #2 this was wrong, after research,
      # only depend on graphical-session but start.
      # But only start after either hyprland or sway start.
      # TODO: (med prio) (research) investigate.
      weakTargets = ["hyprland-session.target" "sway-session.target"];
      strongTargets = ["graphical-session.target"];
      unitRules = {
        # NOTE: make sure that either hyprland or sway along with their
        # target units are started.
        # wants = weakTargets;
        After = weakTargets;
        Requisite = strongTargets;
        # PartOf = strongTargets;
      };
      # wantedRule = unitRules.After;
    in {
      ydotool = {
        Unit = {
          Description = "ydotool user service";
          Documentation = ["man:ydotool(1)"];
        };
        Service = {ExecStart = "${lib.getExe pkgs.ydotool}";};
        Install = {WantedBy = ["default.target"];};
      };
      # NOTE: make this is a template so that this is bound to a target. This is now depends on manager session
      # target.
      # WARN: if the service does not work check user systemd folder in $HOME/.config/systemd/ and see if there a
      # bad symlink
      "shikane@" = let
        target = "%i-session.target";
      in {
        Unit = {
          Description = "Dynamic output configuration for Wayland compositors";
          Documentation = ["man:shikane(1)" "man:shikane(5)"];
          BindsTo = target;
        };
        Service = {
          ExecStart = ''${pkgs.shikane}/bin/shikane'';
          Type = "simple";
          Restart = "always";
          Environment = [
            # TODO: (low prio) this is needed so that exec in shikane works,
            # need to investigate later why,
            # and if its isolated to my machine,home-manager,NixOS, or systemd.
            "PATH=/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
            # NOTE: For now run with trace enabled.
            # "SHIKANE_LOG=trace"
          ];
        };
        Install = {WantedBy = [target];};
      };
      # dunst = {Unit = unitRules;};
      # NOTE: moving from swayidle handling locking to allowing
      # logind (which is better built for this purpose)
    };
    dconf.settings = {
      #"org/gnome/desktop/interface" = {
      #cursor-size = 32;
      #text-scaling-factor = 1;
      #};
      "org/gnome/mutter" = {
        experimental-features = ["scale-monitor-framebuffer"];
      };
      #"org/blueman/general" = { notification-daemon = false; };
      # so nemo (file manager) never displays path as breadcumbs
      "org/nemo/preferences" = {
        show-hidden-files = true;
        show-location-entry = true;
      };
      "org/gtk/settings/file-chooser" = {
        date-format = "regular";
        location-mode = "path-bar";
        show-hidden = true;
        show-size-column = true;
        show-type-column = true;
        sort-column = "modified";
        sort-directories-first = true;
        sort-order = "descending";
        type-format = "category";
      };
    };
    home.sessionVariables = {
      # TODO: (med prio) Move this away from a static variable ( in case sway is run).
      # XDG_SESSION_TYPE = "wayland";
      # GDK_SCALE = "1";
      # QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      # GDK_DPI_SCALE = "1";
      # NOTE: ripped from HiDPI setup, might change scale to 1.25 since that would be the same as 1440p on a 4k 15in display.
      # QT_SCALE_FACTOR = "1.75";
      # QT_FONT_DPI = "75";

      # make sure that apps run under wayland when possible
      NIXOS_OZONE_WL = "1";
      # QT_QPA_PLATFORM = "wayland;xcb";
    };
    xdg = let
      # NOTE: this is so that links are opened in the browser.
      # For some reason the the associations are not being registered.
      # TODO: (low prio) mimeapps already had some entries, include these as well:
      #
      # [Default Applications]
      #
      # [Added Associations]
      # x-scheme-handler/tg=userapp-Kotatogram Desktop-KVRF21.desktop;userapp-Telegram Desktop-ENXU31.desktop;
      # TODO: (high prio) (research) find out why the registration does not
      # happen, and if this only applies to firefx.
      # NOTE: This had to do with some env variables not being set correctly.
      # Fixed in wm config.
      browser = [
        "firefox-developer-edition.desktop"
        # it is assumed this is ordered, which means that developer edition is queried first.
        "firefox-devedition.desktop"
        "firefox.desktop" # assume regular firefox provides this
      ];
      av = [
        "mpv.desktop"
        "vlc.desktop"
      ];
      discord = ["legcord.desktop"];
      associations = {
        # "inode/directory" = ["org.kde.dolphin.desktop"];
        # WARN: this might change, dont know what to do about this.
        "x-scheme-handler/tg" = ["userapp-Telegram Desktop-ENXU31.desktop" "org.telegram.desktop.desktop"];
        "x-scheme-handler/notion" = "notion-app-enhanced.desktop";
        "text/html" = browser;
        "x-scheme-handler/http" = browser;
        "x-scheme-handler/https" = browser;
        "x-scheme-handler/ftp" = browser;
        "x-scheme-handler/chrome" = browser;
        "x-scheme-handler/about" = browser;
        "x-scheme-handler/unknown" = browser;
        "application/x-extension-htm" = browser;
        "application/x-extension-html" = browser;
        "application/x-extension-shtml" = browser;
        "application/xhtml+xml" = browser;
        "application/x-extension-xhtml" = browser;
        "application/x-extension-xht" = browser;
        "application/json" = browser; # .json
        "application/pdf" = browser; # .pdf
        "image/*" = "feh.desktop";
        "audio/*" = av;
        "video/*" = av;
        "x-scheme-handler/discord" = discord;
      };
    in {
      # NOTE: this used to work auto-magically at some point, do not why it
      # stopped working. Test if manually inserting associations works.
      mime.enable = true;
      mimeApps = {
        enable = true;
        associations.added = associations;
        defaultApplications = associations;
      };
      enable = true;
      userDirs = {
        enable = true;
        createDirectories = true;
      };
      configFile."waybar/" = {
        enable = false;
        source = ./waybar;
      };
      # configFile."mimeapps.list" = lib.mkIf config.xdg.mimeApps.enable {force = true;};
      configFile."shikane/config.toml".text =
        import ../shikane/config.toml.nix {inherit config lib pkgs;};
      configFile."sworkstyle/config.toml".text = ''
        [matching]
        '/(?i)Github.*Firefox/' = ''
        '/npm/' = ''
        '/node/' = ''
        '/yarn/' = ''
        '/.*Notion.*/'='N'
        '/.*Slack.*/'=''
        '/.*calibre.*/'=''
        '/(?i)Youtube.*/' = ''
        '/Picture-in-Picture/' = ''
        '/Private Browsing/' = ''
        '/.*NVIM/' = ''
        'firefox-aurora' = ''
        'kitty' = ''
        'ArmCord' = '󰙯'
        'libreoffice-writer' = '󰈭'
        'libreoffice-calc' = '󰧷'
        'mpv'=''
        'evince' = ''
        'org.telegram.desktop' = ''
        'telegramdesktop' = ''
        'Thunderbird' = ''
        'thunderbird' = ''
        'obsidian' = '󱓩'
        'org.keepassxc.KeePassXC' = ''
        'code' = '󰨞'
        'code-url-handler' = '󰨞'
        'ncspot' = ''
        '/.*scli.*/' = '󱋊'
        # '/.*Visual\sStudio\sCode/' = '󰨞'
      '';
      desktopEntries = {
        feh = let
          fehExec =
            pkgs.writeShellScriptBin "feh.sh"
            ''
              feh -. --start-at ./$(realpath --relative-to=$(dirname %f) %f)
            '';
        in {
          name = "Feh";
          exec = "${lib.getExe fehExec}";
          terminal = false;
          type = "Application";
          icon = "feh";
          comment = "Fast Imlib2-based Image Viewer";
          genericName = "Image viewer";
        };
      };
      portal = {
        # lib.mkDefault
        enable = true;
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
          # xdg-desktop-portal-wlr
          # xdg-desktop-portal-hyprland
          gnome-keyring
        ];
        config = {
          sway = {
            # Use xdg-desktop-portal-gtk for every portal interface...
            default = ["gtk"];
            # ... except for the ScreenCast, Screenshot and Secret
            "org.freedesktop.impl.portal.ScreenCast" = ["wlr"];
            "org.freedesktop.impl.portal.Screenshot" = ["wlr"];
            # ignore inhibit bc gtk portal always returns as success,
            # despite sway/the wlr portal not having an implementation,
            # stopping firefox from using wayland idle-inhibit
            "org.freedesktop.impl.portal.Inhibit" = ["none"];
            # make sure that gnome-keyring is enabled
            "org.freedesktop.impl.portal.Secret" = [
              "gnome-keyring"
            ];
            "org.freedesktop.impl.portal.GlobalShortcuts" = ["none"];
            "org.freedesktop.impl.portal.Location" = ["none"];
          };
          hyprland.default = ["hyprland"];
          common = {
            default = [
              "gtk"
            ];
          };
        };
        xdgOpenUsePortal = true;
      };
    };
    services.swaync = {
      enable = true;
      settings = let
        control-center-width = 400;
        notification-window-width = 300;
      in {
        cssPriority = "user";
        image-visibility = "when-available";
        keyboard-shortcut = true;
        relative-timestamps = true;
        timeout = 5;
        timeout-low = 5;
        timeout-critical = 0;
        script-fail-notify = true;
        transition-time = 200;

        # Layer settings
        layer-shell = true;
        layer = "overlay";
        control-center-layer = "overlay";

        # Notification settings
        positionX = "right";
        positionY = "top";
        notification-2fa-action = true;
        notification-inline-replies = false;
        notification-icon-size = 48;
        notification-body-image-height = 200;
        notification-body-image-width = 200;
        inherit notification-window-width;

        # Control center settings
        inherit control-center-width;
        control-center-positionX = "right";
        control-center-positionY = "top";
        control-center-margin-top = 4;
        control-center-margin-bottom = 4;
        control-center-margin-left = 0;
        control-center-margin-right = 4;
        control-center-exclusive-zone = true;
        fit-to-screen = true;
        hide-on-action = true;
        hide-on-clear = false;

        # default is 500
        # control-center-width = width;
        # notification-window-width = notificationWidth;
        # default is 64
        # notification-icon-size = 32;
        "widgets" = [
          "title"
          "buttons-grid"
          "menubar"
          "volume"
          "mpris"
          "notifications"
          "dnd"
        ];
        "widget-config" = {
          "title" = {
            "text" = "Notifications";
            "clear-all-button" = true;
            "button-text" = "Clear All";
          };
          "dnd" = {
            "text" = "Do Not Disturb";
          };
          "label" = {
            "max-lines" = 5;
            "text" = "Label Text";
          };
          "mpris" = {
            "image-size" = 48;
            "image-radius" = 6;
          };
          volume = {
            label = "";
            show-per-app = true;
            show-per-app-icon = true;
            show-per-app-label = true;
          };
          "menubar" = {
            "menu#power-buttons" = {
              label = "";
              position = "right";
              actions = [
                {
                  label = " Reboot";
                  command = "systemctl reboot";
                }
                {
                  label = " Lock";
                  command = "loginctl lock-session";
                }
                {
                  label = " Logout";
                  command = "swaymsg exit";
                }
                {
                  label = " Shut down";
                  command = "systemctl poweroff";
                }
              ];
            };
          };
          buttons-grid = {
            actions = [
              {
                label = "";
                type = "toggle";
                active = true;
                command = "sh -c '[[ $SWAYNC_TOGGLE_STATE == true ]] && nmcli radio wifi on || nmcli radio wifi off'";
                update-command = "sh -c '[[ $(nmcli radio wifi) == 'enabled' ]] && echo true || echo false'";
              }
              {
                label = "";
                type = "toggle";
                active = true;
                command = "sh -c '[[ $SWAYNC_TOGGLE_STATE == true ]] && && bluetoothctl power on || bluetoothctl power off'";
                update-command = "sh -c ' bluetoothctl show | rg 'PowerState: on' -q && echo true || echo false'";
              }
              {
                label = "󰖁";
                type = "toggle";
                active = false;
                command = " sh -c '[[ $SWAYNC_TOGGLE_STATE = true ]] && wpctl set-mute @DEFAULT_AUDIO_SINK@ 1 || wpctl set-mute @DEFAULT_AUDIO_SINK@ 0'";
                update-command = "sh -c 'wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo true || echo false'";
              }
              {
                label = "󰂛";
                type = "toggle";
                active = false;
                command = "sh -c ' [[ $(swaync-client --get-dnd) ]] && swaync-client --dnd-off || swaync-client --dnd-on'";
                update-command = "sh -c 'swaync-client --get-dnd'";
              }
            ];
          };
        };
      };
      style = let
        # titleTxtSz = 16;
        # bodyTxtSz = 14;
        # widgetTextSz = 20;
        titleTxtSz = builtins.toString 12;
        bodyTxtSz = builtins.toString 10;
        widgetTextSz = builtins.toString 16;
        # titleTxtSz = builtins.toString 9;
        # bodyTxtSz = builtins.toString 7;
        # widgetTextSz = builtins.toString 16;
      in ''
        /* Row contains all other notification elements. */
        .notification-row {
          outline: none;
        }

        /* Background is the next largest element. Just a box behind the notification itself. */
        .notification-background {
          padding: 10px 6px;
        }

        /* An notification is a box that contains actions. */
        .notification {
          border-radius: 12px;
          border: 1px solid rgba(37, 36, 35, 0.9);
          padding: 0;
          background: rgba(50, 48, 47, 0.95);
          box-shadow:
            0 0 0 1px rgba(37, 36, 35, 0.3),
            0 1px 3px 1px rgba(37, 36, 35, 0.7),
            0 2px 6px 2px rgba(37, 36, 35, 0.3);
          font-size: ${bodyTxtSz}px;
        }
        .notification-title {
          font-size: ${titleTxtSz}px;
        }
        .notification-body {
          font-size: ${bodyTxtSz}px;
        }

        /* Just a desktop, non panel notification. */
        .floating-notifications {
          background: transparent;
        }

        /* Content is for example the text of a telegram message, if the default action exists, the content will turn to it. */
        .notification-content {
          background: transparent;
          border-radius: 12px;
          padding: 4px;
        }

        /* An example of a default action - this is the telegram message that will be opened by pressing. */
        .notification-default-action {
          padding: 4px;
          margin: 0;
          background: transparent;
          border: none;
          color: rgb(212, 190, 152);
        }

        .notification-default-action:hover {
          -gtk-icon-effect: none;
          background: rgba(60, 56, 54, 0.95);
        }

        /* Action like the "Mark as read" */
        .notification-action {
          padding: 4px;
          margin: 0;
          background: transparent;
          color: rgb(212, 190, 152);
          border: none;
          border-top: 1px solid rgb(80, 73, 69);
          border-radius: 0;
          border-right: 1px solid rgb(80, 73, 69);
        }

        .notification-action:hover {
          -gtk-icon-effect: none;
          background: rgba(60, 56, 54, 0.95);
        }

        .notification-action:first-child {
          /* add bottom border radius to eliminate clipping */
          border-bottom-left-radius: 12px;
        }

        .notification-action:last-child {
          border-bottom-right-radius: 12px;
          border-right: none;
        }

        /* Reply to message line */
        .inline-reply {
          margin-top: 4px;
        }

        .inline-reply-entry {
          background: rgba(37, 36, 35, 0.95);
          color: rgb(212, 190, 152);
          caret-color: rgb(212, 190, 152);
          border: transparent;
          border-radius: 12px;
        }

        .inline-reply-button {
          margin-left: 4px;
          background: transparent;
          border: 1px solid rgba(124, 111, 100, 0.95);
          border-radius: 12px;
          color: rgb(212, 190, 152);
        }

        .inline-reply-button:disabled {
          background: transparent;
          color: rgba(124, 111, 100, 1);
          border-color: transparent;
        }

        .inline-reply-button:hover {
          background: rgba(80, 73, 69, 0.95);
        }

        /* Notification close button */
        .close-button {
          background: transparent;
          color: rgb(212, 190, 152);
          border-radius: 100%;
          margin-top: 5px;
          margin-right: 5px;
          min-width: 24px;
          min-height: 24px;
        }

        .close-button:hover {
          background: rgba(80, 73, 69, 0.95);
        }

        /* Few other notification settings */
        .image {
          -gtk-icon-effect: none;
          margin: 4px;
        }

        .app-icon {
          -gtk-icon-effect: none;
          -gtk-icon-shadow: 0 1px 4px black;
          margin: 6px;
        }

        .summary {
          font-size: ${titleTxtSz}px;
          font-weight: bold;
          background: transparent;
          color: rgb(212, 190, 152);
        }

        .time {
          font-size: ${titleTxtSz}px;
          font-weight: bold;
          background: transparent;
          color: rgb(212, 190, 152);
        }

        .body {
          font-size: ${bodyTxtSz}px;
          font-weight: normal;
          background: transparent;
          color: rgb(212, 190, 152);
          margin-top: 5px;
        }

        .body-image {
          margin-top: 4px;
          background-color: white;
          border-radius: 12px;
          -gtk-icon-effect: none;
        }

        /* Control-center panel which contains the old notifications + widgets */
        .control-center {
          background: rgba(37, 36, 35, 0.85);
          color: rgb(212, 190, 152);
          border-radius: 12px;
        }

        .control-center-list-placeholder {
          opacity: 0.5;
        }

        .control-center-list {
          background: transparent;
        }

        .blank-window {
          background: transparent;
        }

        /* Notification group in control-center */
        .notification-group-buttons,
        .notification-group-headers {
          color: rgb(212, 190, 152);
        }

        .notification-group-icon {
          color: rgb(212, 190, 152);
        }

        .notification-group-header {
          color: rgb(212, 190, 152);
          font-size: 1.10rem;
        }

        /*** Widgets ***/

        /* Title widget */
        .widget-title {
          color: rgb(212, 190, 152);
          margin: 8px;
          font-size: ${widgetTextSz}px;
        }

        .widget-title > button {
          font-size: ${titleTxtSz}px;
          color: rgb(212, 190, 152);
          text-shadow: none;
          background: rgba(37, 36, 35, 0.9);
          border: 1px solid rgba(124, 111, 100, 0.95);
          border-radius: 12px;
        }

        .widget-title > button:hover {
          background: rgba(80, 73, 69, 0.9);
        }

        /* DND widget */
        .widget-dnd {
          color: rgb(212, 190, 152);
          margin: 8px;
          font-size: 1.1rem;
        }

        .widget-dnd > switch {
          font-size: initial;
          border-radius: 12px;
          background: rgba(37, 36, 35, 0.9);
          border: 1px solid rgba(124, 111, 100, 0.95);
          box-shadow: none;
        }

        .widget-dnd > switch:checked {
          background: rgba(231, 138, 78, 0.9);
        }

        .widget-dnd > switch slider {
          background: rgba(50, 48, 47, 0.95);
          border-radius: 12px;
        }

        /* Volume widget */
        .widget-volume {
          color: rgb(212, 190, 152);
          background-color: rgba(60, 56, 54, 0.95);
          padding: 8px;
          margin: 8px;
          border-radius: 12px;
        }

        /* Backlight widget */
        .widget-backlight {
          color: rgb(212, 190, 152);
          background-color: rgba(60, 56, 54, 0.95);
          padding: 8px;
          margin: 8px;
          border-radius: 12px;
        }
      '';

      # .notification-group .notification-group-headers  {
      #   font-weight: bold;
      #   font-size: ${widgetTextSz}pt;
      # }
      # .notification-group-headers {
      #   font-weight: bold;
      #   color: /*text*/rgb(255, 255, 255);
      #   letter-spacing: 2px;
      # }
      # style = ''
      #   # * {
      #     # font-size: 10px !important;
      #     # transition: 200ms;
      #   # }
      #   .body {
      #     font-size: 10px;
      #     font-weight: normal;
      #     background: transparent;
      #     color: white;
      #     text-shadow: none;
      #   }
      #   .summary {
      #     font-size: 10px;
      #     font-weight: bold;
      #     background: transparent;
      #     color: white;
      #     text-shadow: none;
      #   }
      # '';
    };
    services.dunst = {
      enable = false;
      # package = pkgs.dunst;

      settings = {
        experimental = {per_monitor_dpi = true;};
        global = {
          # Which monitor should the notifications be displayed on.
          monitor = 0;
          # Allow a small subset of html markup:<b></b>, <i></i>, <s></s>, and <u></u>.
          # For a complete reference see
          # <http://developer.gnome.org/pango/stable/PangoMarkupFormat.html>.
          # If markup is not allowed, those tags will be stripped out of the message.
          markup = "full";

          # The format of the message.  Possible variables are:
          #   %a  appname
          #   %s  summary
          #   %b  body
          #   %i  iconname (including its path)
          #   %I  iconname (without its path)
          #   %p  progress value if set ([  0%] to [100%]) or nothing
          # Markup is allowed
          # format = "%I %s %p\\n%b";

          #TODO dynamic fonts
          #font = "Droid Sans 12";
          alignment = "left"; # Options are "left", "center", and "right".

          sort = "yes"; # Sort messages by urgency.
          indicate_hidden = "yes"; # Show how many messages are currently hidden (because of geometry).

          # The frequency with wich text that is longer than the notification
          # window allows bounces back and forth.
          # This option conflicts with "word_wrap".
          # Set to 0 to disable.
          # bounce_freq = 5;

          # Show age of message if message is older than show_age_threshold
          # seconds.
          # Set to -1 to disable.
          show_age_threshold = 60;

          # Split notifications into multiple lines if they don't fit into
          # geometry.
          word_wrap = "yes";

          # Ignore newlines '\n' in notifications.
          ignore_newline = "no";

          # The geometry of the window:
          #   [{width}]x{height}[+/-{x}+/-{y}]
          # The geometry of the message window.
          # The height is measured in number of notifications everything else
          # in pixels.  If the width is omitted but the height is given
          # ("-geometry x2"), the message window expands over the whole screen
          # (dmenu-like).  If width is 0, the window expands to the longest
          # message displayed.  A positive x is measured from the left, a
          # negative from the right side of the screen.  Y is measured from
          # the top and down respectevly.
          # The width can be negative.  In this case the actual width is the
          # screen width minus the width defined in within the geometry option.
          # geometry = "0x4-25+25";

          # Shrink window if it's smaller than the width.  Will be ignored if
          # width is 0.
          # shrink = "yes";

          # Display notification on focused monitor.  Possible modes are:
          #   mouse: follow mouse pointer
          #   keyboard: follow window with keyboard focus
          #   none: don't follow anything
          #
          # "keyboard" needs a windowmanager that exports the _NET_ACTIVE_WINDOW property.
          # This should be the case for almost all modern windowmanagers.
          #
          # If this option is set to mouse or keyboard, the monitor option will be ignored.
          follow = "none";

          # Should a notification popped up from history be sticky or timeout
          # as if it would normally do.
          sticky_history = "yes";

          # Maximum amount of notifications kept in history
          history_length = 20;

          # Display indicators for URLs (U) and actions (A).
          show_indicators = "yes";

          # The height of a single line.  If the height is smaller than the
          # font height, it will get raised to the font height.
          # This adds empty space above and under the text.
          line_height = 0;

          # Draw a line of "separator_height" pixel height between two
          # notifications. Set to 0 to disable.
          separator_height = 1;

          # Padding between text and separator.
          padding = 8;

          # Horizontal padding.
          horizontal_padding = 10;

          # The transparency of the window.  Range: [0; 100].
          # This option will only work if a compositing windowmanager is
          # present (e.g. xcompmgr, compiz, etc.).
          transparency = 15;

          # Define a color for the separator.
          # possible values are:
          #  * auto: dunst tries to find a color fitting to the background;
          #  * foreground: use the same color as the foreground;
          #  * frame: use the same color as the frame;
          #  * anything else will be interpreted as a X color.
          # separator_color = "#454947";

          # Print a notification on startup.
          # This is mainly for error detection, since dbus (re-)starts dunst
          # automatically after a crash.

          #set to true for debugging
          # startup_notification = false;

          # Align icons left/right/off
          icon_position = "left";

          # width = 300;
          # height = 300;
          # offset = "30x50";
          origin = "top-right";
          # origin = "top-center";

          #TODO dynamic theme colours
          #      frame_color = "#dc7f41";

          # Browser for opening urls in context menu.
          browser = "firefox";
          # mouse_left_click = "close_current";
          # mouse_middle_click = "do_action, close_current";
          mouse_left_click = "do_action, close_current";
          mouse_middle_click = "context";
          mouse_right_click = "close_current";
        };
        #      settings = {
        #        global = {
        #          icon_path = let userDir = config.home.homeDirectory;
        #          in "/run/current-system/sw/share/icons/hicolor/32x32/actions:/run/current-system/sw/share/icons/hicolor/32x32/animations:/run/current-system/sw/share/icons/hicolor/32x32/apps:/run/current-system/sw/share/icons/hicolor/32x32/categories:/run/current-system/sw/share/icons/hicolor/32x32/devices:/run/current-system/sw/share/icons/hicolor/32x32/emblems:/run/current-system/sw/share/icons/hicolor/32x32/emotes:/run/current-system/sw/share/icons/hicolor/32x32/filesystem:/run/current-system/sw/share/icons/hicolor/32x32/intl:/run/current-system/sw/share/icons/hicolor/32x32/legacy:/run/current-system/sw/share/icons/hicolor/32x32/mimetypes:/run/current-system/sw/share/icons/hicolor/32x32/places:/run/current-system/sw/share/icons/hicolor/32x32/status:/run/current-system/sw/share/icons/hicolor/32x32/stock:${userDir}/.nix-profile/share/icons/hicolor/32x32/actions:${userDir}/.nix-profile/share/icons/hicolor/32x32/animations:${userDir}/.nix-profile/share/icons/hicolor/32x32/apps:${userDir}/.nix-profile/share/icons/hicolor/32x32/categories:${userDir}/.nix-profile/share/icons/hicolor/32x32/devices:${userDir}/.nix-profile/share/icons/hicolor/32x32/emblems:${userDir}/.nix-profile/share/icons/hicolor/32x32/emotes:${userDir}/.nix-profile/share/icons/hicolor/32x32/filesystem:${userDir}/.nix-profile/share/icons/hicolor/32x32/intl:${userDir}/.nix-profile/share/icons/hicolor/32x32/legacy:${userDir}/.nix-profile/share/icons/hicolor/32x32/mimetypes:${userDir}/.nix-profile/share/icons/hicolor/32x32/places:${userDir}/.nix-profile/share/icons/hicolor/32x32/status:${userDir}/.nix-profile/share/icons/hicolor/32x32/stock:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/actions:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/animations:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/apps:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/categories:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/devices:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/emblems:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/emotes:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/filesystem:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/intl:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/legacy:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/mimetypes:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/places:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/status:/nix/store/az5f49j7gb9wznpgwx75bp505gy7mlvz-hicolor-icon-theme-0.17/share/icons/hicolor/32x32/stock";
        #        };
        #      };
      };
    };
    programs.mpv = {
      enable = true;
      # package = pkgs.emptyDirectory;
      scripts = with pkgs; [
        mpvScripts.mpris
        mpvScripts.uosc
        mpvScripts.thumbfast
        mpvScripts.sponsorblock
      ];
      config = {
        hwdec = "auto";
        osd-bar = false;
        ytdl-format = "bestvideo[height<=?1080]+bestaudio/best";
        vo = "gpu-next";
        gpu-context = "waylandvk";
        gpu-api = "vulkan";
        target-colorspace-hint = true;
        # video-sync = "display-resample";
      };
      scriptOpts = {
        uosc = {
          # Display style of current position. available: line, bar
          timeline_style = "line";
          # Line display style config
          timeline_line_width = 2;
          # Timeline size when fully expanded, in pixels, 0 to disable
          timeline_size = 25;
          # Comma separated states when element should always be fully visible.
          # Available: paused, audio, image, video, idle, windowed, fullscreen
          timeline_persistency = "paused,audio";

          # Top border of background color to help visually separate timeline from video
          timeline_border = 1;
          # When scrolling above timeline, wheel will seek by this amount of seconds.
          # Default uses fast seeking. Add `!` suffix to enable exact seeks. Example: `5!`
          timeline_step = 5;
          # Render cache indicators for streaming content
          timeline_cache = "yes";

          # When to display an always visible progress bar (minimized timeline). Can be: windowed, fullscreen, always, never
          # Can also be toggled on demand with `toggle-progress` command.
          progress = "always";
          progress_size = 4;
          progress_line_width = 4;

          # A comma delimited list of controls above the timeline. Set to `never` to disable.
          # Parameter spec: enclosed in `{}` means value, enclosed in `[]` means optional
          # Full item syntax: `[<[!]{disposition1}[,[!]{dispositionN}]>]{element}[:{paramN}][#{badge}[>{limit}]][?{tooltip}]`
          # Common properties:
          #   `{icon}` - parameter used to specify an icon name (example: `face`)
          #            - pick here: https://fonts.google.com/icons?icon.platform=web&icon.set=Material+Icons&icon.style=Rounded
          # `{element}`s and their parameters:
          #   `{shorthand}` - preconfigured shorthands:
          #        `play-pause`, `menu`, `subtitles`, `audio`, `video`, `playlist`,
          #        `chapters`, `editions`, `stream-quality`, `open-file`, `items`,
          #        `next`, `prev`, `first`, `last`, `audio-device`, `fullscreen`,
          #        `loop-playlist`, `loop-file`, `shuffle`
          #   `speed[:{scale}]` - display speed slider, [{scale}] - factor of controls_size, default: 1.3
          #   `command:{icon}:{command}` - button that executes a {command} when pressed
          #   `toggle:{icon}:{prop}[@{owner}]` - button that toggles mpv property
          #   `cycle:{default_icon}:{prop}[@{owner}]:{value1}[={icon1}][!]/{valueN}[={iconN}][!]`
          #       - button that cycles mpv property between values, each optionally having different icon and active flag
          #       - presence of `!` at the end will style the button as active
          #       - `{owner}` is the name of a script that manages this property if any
          #   `gap[:{scale}]` - display an empty gap
          #       {scale} - factor of controls_size, default: 0.3
          #   `space` - fills all available space between previous and next item, useful to align items to the right
          #           - multiple spaces divide the available space among themselves, which can be used for centering
          #   `button:{name}` - button whose state, look, and click action are managed by external script
          # Item visibility control:
          #   `<[!]{disposition1}[,[!]{dispositionN}]>` - optional prefix to control element's visibility
          #   - `{disposition}` can be one of:
          #     - `idle` - true if mpv is in idle mode (no file loaded)
          #     - `image` - true if current file is a single image
          #     - `audio` - true for audio only files
          #     - `video` - true for files with a video track
          #     - `has_many_video` - true for files with more than one video track
          #     - `has_image` - true for files with a cover or other image track
          #     - `has_audio` - true for files with an audio track
          #     - `has_many_audio` - true for files with more than one audio track
          #     - `has_sub` - true for files with an subtitle track
          #     - `has_many_sub` - true for files with more than one subtitle track
          #     - `has_many_edition` - true for files with more than one edition
          #     - `has_chapter` - true for files with chapter list
          #     - `stream` - true if current file is read from a stream
          #     - `has_playlist` - true if current playlist has 2 or more items in it
          #   - prefix with `!` to negate the required disposition
          #   Examples:
          #     - `<stream>stream-quality` - show stream quality button only for streams
          #     - `<has_audio,!audio>audio` - show audio tracks button for all files that have
          #                                   an audio track, but are not exclusively audio only files
          # Place `#{badge}[>{limit}]` after the element params to give it a badge. Available badges:
          #   `sub`, `audio`, `video` - track type counters
          #   `{mpv_prop}` - any mpv prop that makes sense to you: https://mpv.io/manual/master/#property-list
          #                - if prop value is an array it'll display its size
          #   `>{limit}` will display the badge only if it's numerical value is above this threshold.
          #   Example: `#audio>1`
          # Place `?{tooltip}` after the element config to give it a tooltip.
          # Example implementations:
          #   menu = command:menu:script-binding uosc/menu-blurred?Menu
          #   subtitles = command:subtitles:script-binding uosc/subtitles#sub?Subtitles
          #   fullscreen = cycle:crop_free:fullscreen:no/yes=fullscreen_exit!?Fullscreen
          #   loop-playlist = cycle:repeat:loop-playlist:no/inf!?Loop playlist
          #   toggle:{icon}:{prop} = cycle:{icon}:{prop}:no/yes!
          controls = "subtitles,<has_many_audio>audio,<has_many_video>video,<has_many_edition>editions,<stream>stream-quality";

          controls_size = 32;
          controls_margin = 8;
          controls_spacing = 2;
          top_bar = "never";
          refine = "text_width";

          # Where to display volume controls: none, left, right
          volume = "right";
          volume_size = 40;
          volume_border = 1;
          volume_step = 1;

          # Playback speed widget: mouse drag or wheel to change, click to reset
          speed_step = 0.1;
          speed_step_is_factor = "no";

          # Controls all menus, such as context menu, subtitle loader/selector, etc
          menu_item_height = 36;
          menu_min_width = 260;
          menu_padding = 4;
          # Determines if `/` or `ctrl+f` is required to activate the search, or if typing
          # any text is sufficient.
          # When enabled, you can no longer toggle a menu off with the same key that opened it, if the key is a unicode character.
          menu_type_to_search = "yes";
        };
        thumbfast = {
          spawn_first = true;
          network = true;
          hwdec = true;
        };
      };
      bindings = let
        shaderFolder = ./mpv/shaders;
        aishaders = "${inputs.anime4k}/glsl";
        denoise = "${aishaders}/Denoise";
        deblur = "${aishaders}/Deblur";
        restore = "${aishaders}/Restore";
        upscale = "${aishaders}/Upscale";
      in {
        mbtn_right = "script-binding uosc/menu";
        a = "script-binding uosc/stream-quality";
        c = "script-binding uosc/chapters";
        s = "script-binding uosc/subtitles";
        "CTRL+1" =
          "no-osd change-list glsl-shaders set \""
          + builtins.concatStringsSep ":" [
            "${restore}/Anime4K_Clamp_Highlights.glsl"
            "${restore}/Anime4K_Restore_CNN_M.glsl"
            "${upscale}/Anime4K_Upscale_CNN_x2_M.glsl"
            "${upscale}/Anime4K_AutoDownscalePre_x2.glsl"
            "${upscale}/Anime4K_AutoDownscalePre_x4.glsl"
            "${upscale}/Anime4K_Upscale_CNN_x2_S.glsl"
          ]
          + "\"; show-text \"Anime4K: Mode A (Fast)\"";

        # + builtins.concatStringsSep ":" [
        #   "${shaderFolder}/Anime4K_AutoDownscalePre_x2.glsl"
        #   "${shaderFolder}/Anime4K_AutoDownscalePre_x4.glsl"
        #
        #   "${shaderFolder}/Anime4K_Clamp_Highlights.glsl"
        #
        #   "${shaderFolder}/Anime4K_Restore_CNN_M.glsl"
        #   "${shaderFolder}/Anime4K_Restore_CNN_VL.glsl"
        #
        #   "${shaderFolder}/Anime4K_Upscale_CNN_x2_M.glsl"
        #   "${shaderFolder}/Anime4K_Upscale_CNN_x2_VL.glsl"
        # ]
        # + "\"; show-text \"Anime4K: Mode A+A (HQ)\"";

        "CTRL+0" = "no-osd change-list glsl-shaders clr \"\"; show-text \"GLSL shaders cleared\"";
      };
      profiles = {
        gpu-high = {
          vo = "gpu-next";
          # profile = "gpu-hq";
          # video-sync = "display-resample";
          interpolation = "yes";
          tscale = "oversample";
          ytdl-format = "bestvideo+bestaudio/best";
          x11-bypass-compositor = "yes";
          glsl-shader = "${inputs.mpv-ai-upscale}/mpv user shaders/Photo/4x/AiUpscale_HQ_Sharp_4x_Photo.glsl";
        };
      };
    };
    accounts.email = let
      mkMailAccount = {
        name,
        primary ? false,
      }: let
        address = "${name}@michaelpacheco.org";
      in rec {
        inherit address primary;
        userName = address;
        realName = "Michael Pacheco";
        flavor = "plain";
        notmuch.enable = true;
        imap = {
          host = "mail.michaelpacheco.org";
          port = 993;
          tls = {
            enable = true;
          };
        };
        smtp = {
          host = "mail.michaelpacheco.org";
          port = 465;
          tls = {
            enable = true;
            # useStartTls = true;
          };
        };
        neomutt = {
          enable = true;
          mailboxType = "imap";
        };
        thunderbird = {
          enable = true;
        };
        # passwordCommand = "";
        passwordCommand = "keepassxc-cli show -sa password ~/od-stuff/db.kdbx -y 2:23914791 'eMail/michaelpacheco.org/${name}' -k ~/od-stuff/Fav_Image/IMG_20141116_141942.jpg";
        signature = {
          showSignature = "append";
          text = ''
            Michael Pacheco
          '';
        };
        # TODO: set this up
        # gpg = {
        #   key = "";
        # };
      };
    in {
      maildirBasePath = ".mail";
      accounts = {
        scale = mkMailAccount {
          name = "scale";
          primary = true;
        };
        euserv = mkMailAccount {name = "euserv";};
        mp = mkMailAccount {name = "mp";};
        fly = mkMailAccount {name = "fly";};
        freelance = mkMailAccount {name = "freelance";};
        git = mkMailAccount {name = "git";};
        gpg = mkMailAccount {name = "gpg";};
        github = mkMailAccount {name = "github";};
        hackathon = mkMailAccount {name = "hackathon";};
        ibm = mkMailAccount {name = "ibm";};
        jobs = mkMailAccount {name = "jobs";};
        li = mkMailAccount {name = "li";};
        michael = mkMailAccount {name = "michael";};
        rei = mkMailAccount {name = "rei";};
        school = mkMailAccount {name = "school";};
        volunteer = mkMailAccount {name = "volunteer";};
        vpswala = mkMailAccount {name = "vpswala";};
      };
    };

    programs.neomutt = {
      enable = false;
      # vimKeys = true;
      package = pkgs.emptyDirectory;
      sidebar = {
        enable = true;
      };
      sort = "reverse-date";
    };
    programs.thunderbird = {
      enable = true;
      # package = pkgs.emptyDirectory;
      profiles = {
        "main" = {
          isDefault = true;

          settings = {
            "calendar.alarms.showmissed" = false;
            "calendar.alarms.playsound" = false;
            "calendar.alarms.show" = false;
          };
        };
      };
    };
    services.swww.enable = true;

    services.hyprpaper = let
      # NOTE: test for now
      geisha = ../../../assets/img/geisha-tattoos-flowers.png;
      treeFlower = ../../../assets/img/red-flowering-tree-illustration-minimalism-texture.jpg;
      samurai = ../../../assets/img/xavier-cuenca-samurai-mountains.jpg;
      hills = ../../../assets/img/chinese-hills.jpg;
      cyber = ../../../assets/img/cyber-asian-girl-1080.png;
      img = treeFlower;
    in {
      enable = false;
      settings = {
        ipc = "off";
        splash = true;
        preload = ["${img}"];
        wallpaper = [
          ",${img}"
        ];
      };
    };
    services.avizo = {
      enable = true;
    };
  _module.args.generatedHyprBinds = hyprBinds;
  _module.args.generatedSwayBinds = swayKeybindings;
  };
}
