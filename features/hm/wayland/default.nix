# ICD STUFF!
# https://github.com/swaywm/sway/issues/1486#issuecomment-2344740148
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./swayidle.nix
    ./waybar
    ./rofi.nix
    ./common.nix
    ./hyprland.nix
    ./sway.nix
  ];
  config = {
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
    # WARN: mpv: 2026-06-18: getting errors trying to build
    programs.mpv = {
      enable = false;
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
  };
}
