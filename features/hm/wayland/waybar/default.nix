{
  pkgs,
  lib,
  config,
  ...
}: let
  waybar-yubikey = pkgs.writeShellScriptBin "waybar-yubikey" (builtins.readFile ./waybar-yubikey.sh);
in {
  config = {
    programs.waybar = {
      enable = true;
      # package = pkgs.latest.waybar;
      package = pkgs.emptyDirectory;
      # package = pkgs.nw.waybar;
      systemd.enable = false;
      settings = {
        sway = {
          position = "top";
          height = 30;
          exclusive = true;
          gtk-layer-shell = true;
          layer = "bottom";
          modules-left = [
            "sway/workspaces"
            "sway/window"
          ];
          modules-right = [
            "mpris"
            "custom/yubikey"
            "idle_inhibitor"
            "pulseaudio"
            "network"
            # "v"
            "cpu"
            "memory"
            "temperature"
            "backlight"
            "battery"
            "clock#time"
            "clock#date"
            "tray"
          ];

          "custom/yubikey" = {
            exec = "${lib.getExe waybar-yubikey}";
            return-type = "json";
          };
          "sway/window" = {
            rewrite = let
              # TODO: might let nvim handle this porion of the config instead.
              mkEntry = regex: icon: {"(.*?\\.(${regex})) (\\+?.*?) - NVIM" = " ${icon} $1 $3";};
            in
              {
                "(.*) — Firefox Developer Edition Private Browsing" = " $1";
                "(.*)Firefox Developer Edition Private Browsing" = "";
                "(.*) — Firefox Developer Edition" = "🌎 $1";
                "(.*)Firefox Developer Edition" = "";
                "(.*) — Visual Studio Code" = "$1 ";
                "(.*)Spotify(.*)" = "Spotify ";
                "(.*) — zsh" = "> [$1]";
                "vim (.*)" = " $1";
                "vim" = "";
                # "(.*) - NVIM" = " $1";
                "michael@nyx:(.*)" = " $1";
                "(.*) [—-] KeePassXC" = ": $1";
                "(.*) Discord (.*)" = "󰙯 : $1 $2";
                "(.*) [—-] Discord" = "󰙯 : $1";
                "nix-tree --derivation (.*)" = "󱄅-󱘎 $1";
                "kitty" = "KITTY";
              }
              // mkEntry "c|h" ""
              // mkEntry "rs" ""
              // mkEntry "nix" "󱄅"
              // mkEntry "go" ""
              // mkEntry "css" ""
              // mkEntry "html" ""
              // mkEntry "js" ""
              // mkEntry "pl" ""
              // mkEntry "rb" ""
              // mkEntry "exs|ex" ""
              // mkEntry "lua" "󰢱"
              // mkEntry "yaml|yml|md" ""
              // mkEntry "py" ""
              // mkEntry "sh|zsh" ""
              // mkEntry "Dockerfile|compose|docker-compose" ""
              // mkEntry "java" ""
              // mkEntry "diff|patch|gitrebase" ""
              // mkEntry "json" ""
              // mkEntry "xml" "󰗀";
            seperate-outputs = true;
            max-length = 200;
          };
          idle_inhibitor = {
            format = "{icon}";
            format-icons = {
              "activated" = "";
              "deactivated" = "";
            };
          };
          tray = {
            spacing = 10;
          };
          # clock = {
          #   "tooltip-format" = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          #   "format-alt" = "{:%Y-%m-%d}";
          # };
          "clock#time" = {
            interval = 10;
            format = "{:%I:%M%p %Z}";
            format-alt = "{:%R %Z}";
            tooltip-format = "{tz_list}";
            timezones = [
              "America/Los_Angeles"
              "America/New_York"
              "Etc/UTC"
            ];
            # tooltip = false;
          };
          "clock#date" = {
            interval = 20;
            format = "{:%D}";
            "tooltip-format" = "<tt><small>{calendar}</small></tt>";
            "calendar" = {
              "mode" = "year";
              "mode-mon-col" = 3;
              "weeks-pos" = "right";
              "on-scroll" = 1;
              "format" = {
                "months" = "<span color='#ffead3'><b>{}</b></span>";
                # "days" = "<span color='#ecc6d9'><b>{}</b></span>";
                "days" = "<span color='#996666'><b>{}</b></span>";
                "weeks" = "<span color='#99ffdd'><b>W{}</b></span>";
                "weekdays" = "<span color='#ffcc66'><b>{}</b></span>";
                # "today" = "<span color='#ff6699'><b>{}</b></span>";
                "today" = "<span color='#ff6666'><b>{}</b></span>";
              };
            };
          };
          cpu = {
            "format" = "{usage}% ";
            "tooltip" = false;
          };
          memory = {
            format = "{}% ";
          };
          temperature = {
            # TODO: make this generic
            hwmon-path = "/sys/class/hwmon/hwmon5/temp1_input";
            critical-threshold = 80;
            format = "{temperatureC}°C";
            format-icons = ["" "" ""];
          };
          backlight = {
            device = "acpi_video1";
            format = "{percent}% {icon}";
            format-icons = ["" "" "" "" "" "" "" "" ""];
          };
          battery = {
            states = {
              good = 84;
              warning = 30;
              critical = 15;
            };
            format = "{capacity}% {icon}";
            format-charging = "{capacity}% ";
            format-plugged = "{capacity}% ";
            format-alt = "{time} {icon}";
            format-icons = ["" "" "" "" ""];
          };
          network = {
            format-wifi = "{essid} ({signalStrength}%) ";
            format-ethernet = "{ipaddr}/{cidr} ";
            tooltip-format = "{ifname} via {gwaddr} ";
            format-linked = "{ifname} (No IP) ";
            format-disconnected = "Disconnected ⚠";
            format-alt = "{ifname}: {ipaddr}/{cidr}";
          };
          pulseaudio = {
            format = "{volume}% {icon} {format_source}";
            format-bluetooth = "{volume}% {icon} {format_source}";
            format-bluetooth-muted = "x {icon} {format_source}";
            format-muted = "x {format_source}";
            format-source = "{volume}% ";
            format-source-muted = "";
            format-icons = {
              headphone = "";
              hands-free = "";
              headset = "";
              phone = "";
              portable = "";
              car = "";
              default = ["" "" ""];
            };
            "on-click" = "pavucontrol";
          };
          # "custom/vpn" = {
          #   format = "{icon} {}";
          #   format-icons = {
          #     connected = "🔐";
          #     none = "🔓";
          #   };
          #   escape = true;
          #   interval = 5;
          #   return-type = "json";
          #   exec = "${lib.getExe vpnStatus}";
          #   on-click = "$HOME/bin/rofi-vpn.sh";
          # };
          mpris = {
            format = "{player} {player_icon} {dynamic}";
            format-paused = "{status_icon} <i>{dynamic:.20}</i>";
            player-icons = {
              default = "▶";
              mpv = "🎵";
            };
            status-icons = {
              "paused" = "⏸";
            };
            ignored-players = ["firefox"];
            max-length = 30;
          };
        };
      };
      style = builtins.readFile ./style.css;
    };
  };
}
