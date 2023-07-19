{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [./swayidle.nix];
  config = let
    hyprland = inputs.hyprland.packages.${pkgs.system};
  in {
    wayland.windowManager.hyprland = let
      # WARN: 23.0.3 mesa works with dpms, 23.1.3 does dont for some reason,
      # this checks if 23.1.4 fixes it.
      # NOTE: mesa 23.1.4 does fix this. dont see it in the changelog,
      # so it might be a regression fix that was not worth noting?
      mesa = pkgs.mesa.overrideAttrs (let
        version = "23.1.4";
        hash = "sha256-cmGhf7lIZ+PcWpDYofEA+gSwy73lHSUwLAhytemhCVk=";
      in
        old: {
          version = "mesa-${version}-pre";
          src = pkgs.fetchurl {
            inherit hash;
            urls = ["https://archive.mesa3d.org/mesa-${version}.tar.xz"];
          };
        });
      wlroots = hyprland.wlroots-hyprland.override {
        wlroots =
          # pkgs
          # .wlroots_0_16
          (pkgs.wlroots_0_16.overrideAttrs (old: {
            src = pkgs.fetchFromGitLab {
              inherit (old.src) owner repo domain rev hash;
          # NOTE: before wlr_output_layer (feb 20 2023)
          # https://gitlab.freedesktop.org/wlroots/wlroots/-/merge_requests/3640
          # https://gitlab.freedesktop.org/wlroots/wlroots/-/commits/master?search=output
          # WORKS
          # rev = "0335ae9566310e1aa06f17a4b87d98775fd03622";
          # hash = "sha256-nFMSo4VsOHZD/UiPkHz2PSMbpSM8s0dHs0s/nUxfQBo=";
          # rev = "9a425841b048897cf3ec38a8fe8376c6561d833a";
          # hash = "sha256-ewTrU4QG5N+k6nCWvjy+HZabPBolOzIgWKIxD4joNps=";
            };
          }))
          .override {
            inherit mesa;
          };
      };
      package = hyprland.default.override {
      # HACK: use current mesa package.
        inherit wlroots mesa;
      };
    in {
      enable = true;
      inherit package;
      systemdIntegration = true;
      xwayland = {
        enable = true;
        hidpi = true;
      };
    };

    home.pointerCursor = {
      #name = "phinger-cursors";
      #package = pkgs.phinger-cursors;
      name = "Adwaita";
      package = pkgs.gnome3.adwaita-icon-theme;
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
        package = pkgs.gnome.adwaita-icon-theme;
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
        name = "Flat-Remix-GTK-Blue-Dark";
        package = pkgs.flat-remix-gtk;

      };
    };
    qt = {
      enable = true;
      platformTheme = "gtk";
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
      unitRules = {
        After = [ "hyprland-session.target" ];
        Requisite = [ "hyprland-session.target" ];
        PartOf = [ "hyprland-session.target" ];
      };
      wantedRule = unitRules.After;
    in {
      ydotool = {
        Unit = {
          Description = "ydotool user service";
          Documentation = [ "man:ydotool(1)" ];
        };
        Service = { ExecStart = "${pkgs.ydotool}/bin/ydotoold"; };
        Install = { WantedBy = [ "default.target" ]; };
      };
      shikane = {
        Unit =
          {
            Description = "Shikane service";
            Documentation = ["man:shikane(1)" "man:shikane(5)"];
          }
          // unitRules;
        Service = {
          ExecStart = "${lib.getExe pkgs.shikane}";
          Type = "simple";
          Restart = "always";
          Environment = [
            # TODO: (low prio) this is needed so that exec in shikane works,
            # need to investigate later why,
            # and if its isolated to my machine,home-manager,NixOS, or systemd.
            "PATH=/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
          ];
        };
        Install = {WantedBy = strongTargets;};
      };
      # for later reading
      # https://pychao.com/2021/02/24/difference-between-partof-and-bindsto-in-a-systemd-unit/
      dunst = { Unit = unitRules; };
    };
    dconf.settings = {
      #"org/gnome/desktop/interface" = {
      #cursor-size = 32;
      #text-scaling-factor = 1;
      #};
      "org/gnome/mutter" = {
        experimental-features = [ "scale-monitor-framebuffer" ];
      };
      "org/blueman/general" = { notification-daemon = false; };
    };
    xdg = {
      enable = true;
      configFile."hypr/hyprland.conf".text =
        import ./hyprland.conf.nix { inherit pkgs; };
      configFile."hypr/hyprlandd.conf".text =
        import ./hyprland.conf.nix { inherit pkgs; };
      configFile."waybar/" = {
        enable = true;
        source = ./waybar;
      };
      configFile."shikane/config.toml".text =
        import ../shikane/config.toml.nix { inherit config lib pkgs; };
    };
    services.dunst = {
      enable = true;
      package = pkgs.unstable.dunst;
    };
  };
}
