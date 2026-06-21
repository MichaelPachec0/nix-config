{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config;
  waybar-yubikey = pkgs.writeShellScriptBin "waybar-yubikey" (builtins.readFile ./waybar-yubikey.sh);
  # Self-restarting waybar launcher, shared with ./sway.nix and ./hyprland.nix
  # through the waybarLaunch module arg so both compositors start the bar the
  # same way.
  wb_keep = pkgs.writeShellApplication {
    name = "wb_keep";
    runtimeInputs = with pkgs; [waybar];
    text = ''
      until waybar; do
        echo "Waybar is dead: exit code ''$?, long live waybar!" >&2
        sleep .5
      done
    '';
  };
  wb_killer = pkgs.writeShellApplication {
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
in {
  config = {
    _module.args.waybarLaunch = "${lib.getExe wb_killer} && ${lib.getExe wb_keep}";
    programs.waybar = {
      enable = true;
      # package = pkgs.latest.waybar;
      package = pkgs.emptyDirectory;
      # package = pkgs.nw.waybar;
      systemd.enable = false;
      settings = let
        vpnStatus = pkgs.writeShellApplication {
          name = "vpn-status";
          text = ''
            vpn_conn=$(systemctl list-units --state=active | sed -n "s/^openvpn-\(\w*\).*$/\1/p" | head -n1)
            if test "$vpn_conn" = ""; then
                echo '{"text": "󰒙", "alt": "none", "tooltip": "No VPN"}'
            else
                echo "{\"text\": \"󰕥\", \"tooltip\": \"''${vpn_conn^}\", \"alt\": \"connected\"}"
            fi
          '';
        };
        windowModule = {
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
          separate-outputs = true;
          max-length = 200;
        };
      in {
        mainBar = {
          position = "top";
          height = 30;
          exclusive = true;
          gtk-layer-shell = true;
          layer = "bottom";
          modules-left = [
            "sway/workspaces"
            "hyprland/workspaces"
            "sway/window"
            "hyprland/window"
          ];
          # Active-mode indicator (sway's resize mode / Hyprland submaps like the
          # group_with submap). Only one renders per compositor; both are hidden
          # when no mode/submap is active.
          modules-center = [
            "sway/mode"
            "hyprland/submap"
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
          "hyprland/workspaces" = {
            on-click = "activate";
            format = "{name}";
          };
          "sway/window" = windowModule;
          "hyprland/window" = windowModule;
          # "{}" is the mode/submap name -> e.g. "resize mode", "groupwith mode".
          "sway/mode" = {
            format = "{} mode";
            tooltip = false;
          };
          "hyprland/submap" = {
            format = "{} mode";
            tooltip = false;
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
