{ config, lib, pkgs, ... }:
let bin = "/run/current-system/sw/bin";
  scale = "1.75";
  RD = pkgs.writeShellScriptBin "rotate_display.sh" ''
    function build_command(){
        if [[ $XDG_CURRENT_DESKTOP == "sway"  ]]; then
          # NOTE: grabs the right display
          # TODO: make this more generic
          display=$(swaymsg -t get_outputs  | rg \"DP | tr -d " " | cut -d ":" -f 2 | sed 's/\"\(.*\)\",/\1/')
          display_debug=$(swaymsg -t get_outputs  | rg \"DP | tr -d " ")
          # NOTE: was DP-2, transform  270.
          echo "DEBUG $display_debug"
          echo "DEBUG2: $(swaymsg -t get_outputs)"
          if [[ $1 == 1 ]]; then
            set --  "270"
          fi
          command="swaymsg -- output $display transform $1"
        elif [[ $XDG_CURRENT_DESKTOP == "hyprland" ]]; then
          # NOTE: was DP-2. transform was 1 (90)
          # TODO: fix this, the function is not getting two variables anymorej
          command="hyprctl keyword monitor $1, transform,$2"
        else
            echo "INVALID ENV! ENV: $XDG_CURRENT_DESKTOP "
        fi
        echo "DEBUG: executing $command"
        $command
    }
    # NOTE: for now only rotate the mobile monitor, might want to later not
    # hardcode this.
    build_command 1
  '';
in ''
  [[ profile ]]
  name = "default"
  [[ profile.output ]]
  match = "eDP-1"
  enable = true
  mode = { width = 3840, height = 2160, refresh = 59.99 }
  position = { x = 0, y = 0 }
  scale = ${scale}

  [[ profile ]]
  name = "mobile with monitor"
  exec = ["${lib.getExe RD}"]
  [[ profile.output ]]
  match = "eDP-1"
  enable = true
  mode = { width = 3840, height = 2160, refresh = 59.99 }
  position = { x = 1080, y = 0 }
  scale = 1.5
  [[ profile.output ]]
  match  = "DP-1"
  enable = true
  mode = { width = 1920, height = 1080, refresh = 60.00 }
  position = { x = 0, y = 0 }
  scale = 1.0
  exec = [ "${config.wayland.windowManager.hyprland.package}/bin/hyprctl keyword monitor DP-1, transform,1" ]
  #exec = [ "${bin}/hyprctl " ]
  #exec = [ "/bin/sh -c 'echo hello world'" ]
  #exec = [ "${lib.getExe pkgs.bash} -c 'echo hello world'" ]
  [[ profile ]]
  name = "Home Docked"
  [[ profile.output ]]
  match = "eDP-1"
  enable = true
  mode  = { width = 3840, height = 2160, refresh = 59.99 }
  position  = { x = 0, y = 0 }
  scale = ${scale}
  [[ profile.output ]]
  match = "/VG279/"
  enable = true
  mode = { width = 1920, height = 1080, refresh = 144 }
  position  = { x = 2560, y = 0 }
  scale = 1.0
  [[ profile.output ]]
  match = "/ET241Y/"
  enable = true
  mode = { width = 1920, height = 1080, refresh = 60 }
  position = { x = 4480, y = 0 }
  scale = 1.0


  [[ profile ]]
  name = "Home Only Asus"
  [[ profile.output ]]
  match = "eDP-1"
  enable = true
  mode  = { width = 3840, height = 2160, refresh = 59.99 }
  position  = { x = 0, y = 0 }
  scale = 1.5
  [[ profile.output ]]
  match = "/VG279/"
  enable = true
  mode = { width = 1920, height = 1080, refresh = 120 }
  position  = { x = 2560, y = 0 }
  scale = 1.0

  [[ profile ]]
  name = "LN profile"
  exec = [
    "${lib.getExe RD}",
  ]
  [[ profile.output ]]
  match = "eDP-1"
  enable = true
  mode = { width = 3840, height = 2160, refresh = 59.99 }
  position = { x = 1080, y = 1080 }
  scale = ${scale}
  [[ profile.output ]]
  match  = "DP-2"
  enable = true
  mode = { width = 1920, height = 1080, refresh = 60.00 }
  position = { x = 3640, y = 0 }
  scale = 1.0
  exec = [ "${config.wayland.windowManager.hyprland.package}/bin/hyprctl keyword monitor DP-2, transform,1" ]
  #exec = [ "${bin}/hyprctl " ]
  #exec = [ "/bin/sh -c 'echo hello world'" ]
  #exec = [ "${lib.getExe pkgs.bash} -c 'echo hello world'" ]
  [[ profile.output ]]
  match  = "/OptiPlex 7460/"
  enable = true
  mode = { width = 1920, height = 1080, refresh = 60.00 }
  position = { x = 1080, y = 0 }
  scale = 1.0

  [[ profile ]]
  name = "LV profile"
  exec = [
    "${lib.getExe RD}",
  ]
  [[ profile.output ]]
  match = "eDP-1"
  enable = true
  mode = { width = 3840, height = 2160, refresh = 59.99 }
  position = { x = 1080, y = 1080 }
  scale = ${scale}
  [[ profile.output ]]
  match  = "DP-2"
  enable = true
  mode = { width = 1920, height = 1080, refresh = 60.00 }
  position = { x = 0, y = 0 }
  scale = 1.0
  [[ profile.output ]]
  match  = "/Samsung Electric Company S22C650/"
  enable = true
  mode = { width = 1920, height = 1080, refresh = 60.00 }
  position = { x = 1080, y = 0 }
  scale = 1.0
''
