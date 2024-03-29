{pkgs, ...}: let
  cursorSZ = "24";
  scale = "2";
in ''
  # See https://wiki.hyprland.org/Configuring/Monitors/
  # See Xwayland config https://wiki.hyprland.org/Configuring/XWayland/#hidpi-xwaylands
  #monitor=,highres,auto,${scale}
  # exec = xprop -root -f _XWAYLAND_GLOBAL_OUTPUT_SCALE ${cursorSZ}c -set _XWAYLAND_GLOBAL_OUTPUT_SCALE ${scale}
  env = XCURSOR_SIZE,${cursorSZ}
  monitor=,preferred,auto,auto



  # See https://wiki.hyprland.org/Configuring/Keywords/ for more


  # Execute your favorite apps at launch
  # exec-once = waybar & hyprpaper & firefox
  exec-once= dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP
  exec-once = systemctl --user import-environment
  # enable notification daemon, copy and paste provider 
  exec-once = waybar & cliphist
  # Source a file (multi-file configs)
  # source = ~/.config/hypr/myColors.conf
  exec-once = polychromatic-cli -o brightness -p 100 && polychromatic-cli -o reactive medium

  # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
  input {
      kb_layout = us
      kb_variant =
      kb_model =
      kb_options =
      kb_rules =

      follow_mouse = 1

      touchpad {
        natural_scroll = true
  	    tap-to-click = false
  	    disable_while_typing = true
      }

      sensitivity = 0 # -1.0 - 1.0, 0 means no modification.
  }

  general {
      # See https://wiki.hyprland.org/Configuring/Variables/ for more

      gaps_in = 5
      gaps_out = 10
      border_size = 2
      col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
      col.inactive_border = rgba(595959aa)

      layout = dwindle
      resize_on_border = true
  }

  decoration {
      # See https://wiki.hyprland.org/Configuring/Variables/ for more

      rounding = 5
      # was true
      blur {
        enabled = true
        size = 5
        passes = 1
        new_optimizations = true
        # xray = true
      }

      drop_shadow = false
      shadow_range = 4
      shadow_render_power = 3
      col.shadow = rgba(1a1a1aee)
  }

  animations {
      # was true
      enabled = false

      # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

      bezier = myBezier, 0.05, 0.9, 0.1, 1.05

      animation = windows, 1, 7, myBezier
      animation = windowsOut, 1, 7, default, popin 80%
      animation = border, 1, 10, default
      animation = borderangle, 1, 8, default
      animation = fade, 1, 7, default
      animation = workspaces, 1, 6, default
  }

  dwindle {
      # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
      pseudotile = true # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
      preserve_split = true # you probably want this
  }

  master {
      # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
      new_is_master = true
  }

  gestures {
      # See https://wiki.hyprland.org/Configuring/Variables/ for more
      workspace_swipe = true
  }

  misc {
  	disable_splash_rendering = true 
    vfr = true
  	# vrr = 0
    # TODO: RE-ENABLE AFTER TEST
    key_press_enables_dpms = true
  	mouse_move_enables_dpms = true
    # apperantly there is performance on the table to be had when disbling it
    disable_hyprland_logo = true
    suppress_portal_warnings = true
  }
  xwayland {
    force_zero_scaling = true
  }

  # Example per-device config
  # See https://wiki.hyprland.org/Configuring/Keywords/#executing for more
  device:epic-mouse-v1 {
      sensitivity = -0.5
  }

  # Example windowrule v1
  # windowrule = float, ^(kitty)$
  # Example windowrule v2
  # windowrulev2 = float,class:^(kitty)$,title:^(kitty)$
  # See https://wiki.hyprland.org/Configuring/Window-Rules/ for more
  windowrulev2 = opacity 0.94 0.94,class:Code|Slack|ArmCord|^(kitty)$
  # throw sharing indicators away
  windowrulev2 = workspace special silent, title:^(Firefox.* — Sharing Indicator)$
  windowrulev2 = workspace special silent, title:^(.*is sharing (your screen|a window)\.)$

  # See https://wiki.hyprland.org/Configuring/Keywords/ for more
  $mainMod = SUPER

  # Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
  bind = $mainMod, T, exec, kitty
  bind = $mainMod, Y, exec, foot
  bind = $mainMod, K, killactive,
  bind = $mainMod, Q, exit,
  bind = $mainMod, E, exec, nemo
  #bind = $mainMod, W, exec, librewolf
  bind = $mainMod, W, exec, firefox-devedition
  bind = $mainMod, F, togglefloating,
  bind = $mainMod, SPACE, exec, rofi -show drun
  bind = $mainMod, P, pseudo, # dwindle
  bind = $mainMod, J, togglesplit, # dwindle

  # Use rofi to display clipboard history
  bind = SUPER, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy

  # Move focus with mainMod + arrow keys
  bind = $mainMod, left, movefocus, l
  bind = $mainMod, right, movefocus, r
  bind = $mainMod, up, movefocus, u
  bind = $mainMod, down, movefocus, d
  # bind = $mainMod, h, movefocus, l
  # bind = $mainMod, l, movefocus, r
  # bind = $mainMod, j, movefocus, u
  # bind = $mainMod, k, movefocus, d


  # Switch workspaces with mainMod + [0-9]
  bind = $mainMod, 1, workspace, 1
  bind = $mainMod, 2, workspace, 2
  bind = $mainMod, 3, workspace, 3
  bind = $mainMod, 4, workspace, 4
  bind = $mainMod, 5, workspace, 5
  bind = $mainMod, 6, workspace, 6
  bind = $mainMod, 7, workspace, 7
  bind = $mainMod, 8, workspace, 8
  bind = $mainMod, 9, workspace, 9
  bind = $mainMod, 0, workspace, 10

  # Move active window to a workspace with mainMod + SHIFT + [0-9]
  bind = $mainMod SHIFT, 1, movetoworkspace, 1
  bind = $mainMod SHIFT, 2, movetoworkspace, 2
  bind = $mainMod SHIFT, 3, movetoworkspace, 3
  bind = $mainMod SHIFT, 4, movetoworkspace, 4
  bind = $mainMod SHIFT, 5, movetoworkspace, 5
  bind = $mainMod SHIFT, 6, movetoworkspace, 6
  bind = $mainMod SHIFT, 7, movetoworkspace, 7
  bind = $mainMod SHIFT, 8, movetoworkspace, 8
  bind = $mainMod SHIFT, 9, movetoworkspace, 9
  bind = $mainMod SHIFT, 0, movetoworkspace, 10

  # Scroll through existing workspaces with mainMod + scroll
  bind = $mainMod, mouse_down, workspace, e+1
  bind = $mainMod, mouse_up, workspace, e-1

  # Move/resize windows with mainMod + LMB/RMB and dragging
  bindm = $mainMod, mouse:272, movewindow
  bindm = $mainMod, mouse:273, resizewindow

  # Volume Keybinds
  bind = , XF86AudioRaiseVolume,    exec, playerctl volume 0.1+
  bind = , XF86AudioLowerVolume,    exec, playerctl volume 0.1-
  #bind = , XF86AudioMute,      exec,  exec, amixer set Master toggle
  # Other Audio related keybinds
  bind = , XF86AudioNext, 	exec, playerctl next
  bind = , XF86AudioPrev,		exec, playerctl previous
  bind = , XF86AudioPlay, 	exec, playerctl play-pause


  # brightness keybinds
  bind = , XF86MonBrightnessUp,     exec, brightnessctl set 10%+
  bind = , XF86MonBrightnessDown,   exec, brightnessctl set 10%-

  #bind = , XF86MonBrightnessUp,     exec, brillo -q -A 5
  #bind = , XF86MonBrightnessDown,   exec, brillo -q -U 5

''
