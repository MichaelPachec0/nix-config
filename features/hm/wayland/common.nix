# Shared Wayland window-manager keybindings.
#
# swayKeybindings is the single source of truth: ./sway.nix consumes it
# directly, while ./hyprland.nix derives its binds from it through toHypr.
# Both are published as module args (generatedSwayBinds / generatedHyprBinds)
# so the two compositor modules can use them without importing each other.
{
  config,
  lib,
  pkgs,
  ...
}: let
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

      else if cmd == "focus parent" then
        # hy3: raise focus to the parent group (e.g. the whole tab stack).
        "hy3:changefocus, raise"

      else if cmd == "focus child" then
        # hy3: lower focus back into the focused group's child node.
        "hy3:changefocus, lower"

      else if lib.hasPrefix "focus " cmd then
        let dir = lib.removePrefix "focus " cmd;
        # hy3:movefocus is tree-aware -- it steps in/out of tab groups and
        # splits correctly, unlike the native movefocus.
        in "hy3:movefocus, ${dirMap.${dir} or dir}"

      else if lib.hasPrefix "workspace number " cmd then
        "workspace, ${lib.removePrefix "workspace number " cmd}"

      else if lib.hasPrefix "move container to workspace number " cmd then
        # hy3:movetoworkspace moves the focused node (a window or a whole
        # group/tab stack) without following -- matches sway's move container.
        "hy3:movetoworkspace, ${lib.removePrefix "move container to workspace number " cmd}"

      # move container direction
      else if lib.hasPrefix "move " cmd then
        let dir = lib.removePrefix "move " cmd;
        in "hy3:movewindow, ${dirMap.${dir} or dir}"

      else if cmd == "floating toggle" then
        "togglefloating"

      else if cmd == "fullscreen toggle" then
        "fullscreen"

      else if cmd == "scratchpad show" then
        "togglespecialworkspace, magic"

      else if cmd == "move scratchpad" then
        "movetoworkspace, special:magic"

      else if cmd == "splith" then
        "hy3:makegroup, h"

      else if cmd == "splitv" then
        "hy3:makegroup, v"

      else if cmd == "layout toggle split" then
        "hy3:changegroup, opposite"

      # hy3 has no stacking layout; both "stacking" and "tabbed" map to tabs.
      else if cmd == "layout stacking" then
        "hy3:makegroup, tab"

      else if cmd == "layout tabbed" then
        "hy3:makegroup, tab"

      else if cmd == "mode 'resize'" then
        "submap, resize"

      else
        "exec, ${cmd}";

  in
    "${mods}, ${key}, ${action}";

  hyprBinds =
    lib.mapAttrsToList toHypr swayKeybindings;
in {
  _module.args.generatedSwayBinds = swayKeybindings;
  _module.args.generatedHyprBinds = hyprBinds;
}
