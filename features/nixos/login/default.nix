{
  config,
  lib,
  pkgs,
  ...
}: let
  cfgGL = config.services.graphicalLogin;
  cfg = config;
in {
  #imports = [ ../../../pkgs/regreet ];
  options = {
    services = {
      graphicalLogin = {
        enable =
          lib.mkEnableOption "Setups greetd and other login configuration.";
        wallpaper = lib.mkOption {
          default = null;
          type = lib.types.nullOr lib.types.path;
          description = lib.mdDoc ''
            path to the wallpaper wanted
          '';
        };
      };
    };
  };
  config = lib.mkIf cfgGL.enable {
    # use sway as backend compositor, since it displays correctly on HiDPI
    # Do not set anything else, sway on nixos at least already has sane defaults
    # User setup can happen on home-manager for the user
    # use regreet as the greetd DM
    programs.regreet = {
      enable = true;
      # HACK: because of https://github.com/rharish101/ReGreet/issues/32
      # use commit before the multimonitor fix.
      # TODO: (high prio) (short term, ovl) break this out into its own module.
      # NOTE: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/rust.section.md
      # TODO: (low prio) (upstream) Check upstream if there is a new release that fixes this bug.
      package = pkgs.regreet;
      # package = pkgs.greetd.regreet.overrideAttrs (old: rec {
      #   version = "0.1.0-custom";
      #   src = pkgs.fetchFromGitHub {
      #     inherit (old.src) owner repo;
      #     rev = "ccffff87f621d9ea0d3c0f6ca64b361509d1dbc3";
      #     hash = "sha256-6VdM7W8Sx+D6Lp8LijuWWvGhRS+QIW4CWn1OATGqBPc=";
      #   };
      #   cargoDeps = old.cargoDeps.overrideAttrs (_: {
      #     inherit src;
      #     # NOTE: this is what is needed to compute the cargoHash
      #     # outputHash = lib.fakeHash;
      #     outputHash = "sha256-M1ha8tL5j5B1wOOrBRQ7qEDbsaSzfrluqT35W9RWluI=";
      #   });
      # });
      # do not set settings here yet
      theme = {
        package = pkgs.gruvbox-gtk-theme.override {
          themeVariants = ["all"];
          tweakVariants = ["macos"];
        };
        # /nix/store/<theme>/share/themes/
        # the name will specified there
        name = "Gruvbox-Yellow-Dark";
      };
      font = {
        size = 8;
      };
      settings = {
        background = let
          path = "${../../../assets/img/gruvbox_lady.png}";
        in {
          # Path to the background image
          # path = "/usr/share/backgrounds/greeter.jpg"
          inherit path;

          # How the background image covers the screen if the aspect ratio doesn't match
          # Available values: "Fill", "Contain", "Cover", "ScaleDown"
          # Refer to: https://docs.gtk.org/gtk4/enum.ContentFit.html
          # NOTE: This is ignored if ReGreet isn't compiled with GTK v4.8 support.
          fit = "Contain";

          # The entries defined in this section will be passed to the session as environment variables when it is started
        };
        GTK = {
          # Whether to use the dark theme
          application_prefer_dark_theme = true;
          # cursor_theme_name = "Bibata-Modern-Classic";
          # font_name = "Jost * 12";
          # icon_theme_name = "Papirus-Dark";
          # theme_name = "Catppuccin-Mocha-Compact-Mauve-Dark";

          # Cursor theme name
          cursor_theme_name = "Adwaita";

          # Icon theme name
          icon_theme_name = "Adwaita";

          # GTK theme name
          # theme_name = "Gruvbox-Dark""
          # theme_name = "Adwaita";
        };
        env = {
          # NOTE: will test this after. if the former does not works
          # for some reason this works only if not
          WLR_DRM_NO_MODIFIERS = "1";
          GDK_BACKEND = "wayland";
        };
        commands = {
          reboot = ["systemctl" "reboot"];
          poweroff = ["systemctl" "poweroff"];
        };
        "widget.clock" = {
          # strftime format argument
          # See https://docs.rs/jiff/0.1.14/jiff/fmt/strtime/index.html#conversion-specifications
          format = "%a %H:%M";

          # How often to update the text
          resolution = "500ms";

          # Override system timezone (IANA Time Zone Database name, aka /etc/zoneinfo path)
          # Remove to use the system time zone.
          timezone = "America/Los_Angeles";

          # Ask GTK to make the label at least this wide. This helps keeps the parent element layout and width consistent.
          # Experiment with different widths, the interpretation of this value is entirely up to GTK.
          label_width = "150";
        };
      };
      # NOTE: refer to the inspector (use regreet demo) and gtk inspector
      #   ref: https://github.com/rharish101/ReGreet/issues/116#issuecomment-2817284742
      extraCss = ''
        picture {
          filter: blur(0.05rem);
        }
        frame.background {
          opacity: 0.9;
        }
      '';
    };
    # TODO: (low prio) move this away from here.
    # It is here for the dbus commands usage.
    environment.systemPackages = with pkgs; [
      dbus
      (catppuccin-gtk.override {
        accents = ["mauve"];
        size = "compact";
        variant = "mocha";
      })
      (pkgs.gruvbox-gtk-theme.override {
        themeVariants = ["all"];
        tweakVariants = ["macos"];
        # iconVariants = ["Dark"];
      })

      bibata-cursors
      papirus-icon-theme
      # pkgs.nw.swayfx
    ];
    # enable geetd
    services.greetd = {
      enable = true;
      # restart on logout
      restart = true;
      settings = {
        default_session = {
          # command = "${lib.getExe cfg.programs.sway.package} --config /etc/greetd/sway-config";
          command = let
            extraSessionCommands = ''
              export WLR_DRM_NO_MODIFIERS=1
            '';
            # sway = pkgs.stable.sway.override {inherit extraSessionCommands;};
            sway = pkgs.sway.override {inherit extraSessionCommands;};
          in "${lib.getExe sway} --config /etc/greetd/sway-config";
          # command = "${lib.getExe pkgs.cage} -s -- ${lib.getExe pkgs.greetd.regreet}";
          user = "greeter";
        };
      };
    };
    #
    # environment.etc."greetd/environments".text = ''
    #   Hyprland
    #   sway
    #   zsh
    # '';
    # environment.etc."greetd/regreet.toml".text = lib.mkDefault ''
    #   # [GTK]
    #   # application_prefer_dark_theme = true
    #   # cursor_theme_name = "Adwaita"
    #   # font_name = "Cantarell 16"
    #   # icon_theme_name = "Adwaita"
    #   # theme_name = "Gruvbox-Yellow-Dark"
    #   #
    #   # [background]
    #   # path = "/etc/greetd/wallpaper.jpg"
    #   #
    #   # [commands]
    #   # poweroff = ["systemctl", "poweroff"]
    #   # reboot = ["systemctl", "reboot"]
    #   #
    #   # [env]
    #   # GDK_BACKEND = "wayland"
    #   # WLR_DRM_NO_MODIFIERS = 1
    #
    #   # SPDX-FileCopyrightText: 2022 Harish Rajagopal <harish.rajagopals@gmail.com>
    #   #
    #   # SPDX-License-Identifier: GPL-3.0-or-later
    #
    #   [background]
    #   # Path to the background image
    #   # path = "/usr/share/backgrounds/greeter.jpg"
    #   path = "/etc/greetd/wallpaper.jpg"
    #
    #   # How the background image covers the screen if the aspect ratio doesn't match
    #   # Available values: "Fill", "Contain", "Cover", "ScaleDown"
    #   # Refer to: https://docs.gtk.org/gtk4/enum.ContentFit.html
    #   # NOTE: This is ignored if ReGreet isn't compiled with GTK v4.8 support.
    #   fit = "Contain"
    #
    #   # The entries defined in this section will be passed to the session as environment variables when it is started
    #   [env]
    #   GDK_BACKEND = "wayland"
    #   WLR_DRM_NO_MODIFIERS = "1"
    #
    #   [GTK]
    #   # Whether to use the dark theme
    #   application_prefer_dark_theme = true
    #
    #   # Cursor theme name
    #   cursor_theme_name = "Adwaita"
    #
    #   # Font name and size
    #   font_name = "Cantarell 16"
    #
    #   # Icon theme name
    #   icon_theme_name = "Adwaita"
    #
    #   # GTK theme name
    #   # theme_name = "Gruvbox-Dark""
    #   theme_name = "Adwaita"
    #
    #   [commands]
    #   # The command used to reboot the system
    #   reboot = ["systemctl", "reboot"]
    #
    #   # The command used to shut down the system
    #   poweroff = ["systemctl", "poweroff"]
    #
    #   # The command prefix for X11 sessions to start the X server
    #
    #   [appearance]
    #   # The message that initially displays on startup
    #   greeting_msg = "Welcome back!"
    #
    #
    #   [widget.clock]
    #   # strftime format argument
    #   # See https://docs.rs/jiff/0.1.14/jiff/fmt/strtime/index.html#conversion-specifications
    #   format = "%a %H:%M"
    #
    #   # How often to update the text
    #   resolution = "500ms"
    #
    #   # Override system timezone (IANA Time Zone Database name, aka /etc/zoneinfo path)
    #   # Remove to use the system time zone.
    #   timezone = "America/Los_Angeles"
    #
    #   # Ask GTK to make the label at least this wide. This helps keeps the parent element layout and width consistent.
    #   # Experiment with different widths, the interpretation of this value is entirely up to GTK.
    #   label_width = 150
    # '';
    # environment.etc."greetd/wallpaper.jpg" = {
    #   source = ../../../assets/img/wallpaper_gruvbox_lady.png;
    # };
    environment.etc."greetd/sway-config".text = ''
      exec "dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP"
      # Dont need xwayland
      xwayland disable
      # Set brightness keys
      bindsym XF86MonBrightnessUp exec brightnessctl set 10%+
      bindsym XF86MonBrightnessDown exec brightnessctl set 10%-
      # Enable the touchpad
      input "type:touchpad" {
        tap enabled
      }
      seat seat0 xcursor_theme Bibata-Modern-Classic 24
      # make sure that we can exit with the kb
      bindsym Mod4+shift+q exec swaynag \
        -t warning \
        -m 'What do you want to do?' \
        -b 'Poweroff' 'systemctl poweroff' \
        -b 'Reboot' 'systemctl reboot'

      # TODO: make sure to clean up the log file here.
      exec "${lib.getExe cfg.programs.regreet.package} -L trace -l /tmp/regreet_$(date +%Y-%m-%d_%H:%M).log;  swaymsg exit"
      include /etc/sway/config.d/*
    '';

    systemd.tmpfiles.rules = [
      "d /var/log/regreet 0755 greeter greeter - -"
      "d /var/cache/regreet 0755 greeter greeter - -"
    ];
    security.pam.services.greetd.enableGnomeKeyring = true;

    # environment.etc."xdg/wayland-sessions/swayfx-greeter.desktop".text = ''
    #   [Desktop Entry]
    #   Name=SwayFX
    #   Exec=${lib.getExe pkgs.nw.swayfx}
    #   Type=Application
    #   DesktopNames=SwayFX
    # '';
  };
}
# swayConfig = pkgs.writeText "greetd-sway-config" ''
#     # `-l` activates layer-shell mode. Notice that `swaymsg exit` will run after gtkgreet.
#     exec "${pkgs.greetd.regreet}/bin/regreet -l debug  &> /tmp/regreet.log; swaymsg exit"
#     bindsym Mod4+shift+e exec swaynag \
# 	-t warning \
# 	-m 'What do you want to do?' \
# 	-b 'Poweroff' 'systemctl poweroff' \
# 	-b 'Reboot' 'systemctl reboot'
#     include /home/gergoe/.config/sway/config
#   '';

