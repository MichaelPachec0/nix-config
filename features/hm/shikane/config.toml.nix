{ config, lib, pkgs, ... }:
let bin = "/run/current-system/sw/bin";
in ''
  [[ profile ]]
  name = "default"
  [[ profile.output ]]
  match = "eDP-1"
  enable = true
  mode = { width = 3840, height = 2160, refresh = 59.99 }
  position = { x = 0, y = 0 }
  scale = 1.5

  [[ profile ]]
  name = "mobile with monitor"
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
  scale = 1.5
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
''
