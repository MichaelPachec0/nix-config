# Hyprland compositor configuration (Lua config via home-manager configType).
#
# Keybinds come from ./common.nix via the generatedLuaBinds module arg (the
# shared sway keybindings translated through toLua). configType = "lua" makes
# home-manager serialize `settings` to ~/.config/hypr/hyprland.lua: each
# top-level settings key becomes an hl.<key>(...) call, and once the .lua
# exists Hyprland ignores hyprland.conf entirely (lua vs hyprlang is
# all-or-nothing). See the home-manager hyprland module lib.nix for the
# serializer, and the parity notes in ./common.nix (toLua).
{
  config,
  lib,
  pkgs,
  generatedLuaBinds,
  waybarLaunch,
  ...
}: let
  firefox = "${lib.getExe config.programs.firefox.package}";
  inherit (lib.generators) mkLuaInline;
  luaStr = s: lib.generators.toLua {} s;

  # hy3 dispatcher binds with no sway equivalent (appended to generatedLuaBinds).
  # hy3 lua functions are wrapped in `function() .. end`: hl.plugin.hy3.* is only
  # registered after the plugin loads at startup, so a bare reference would be
  # nil at config-parse time. Arg shapes verified against hy3 src/dispatchers.cpp.
  hy3ExtraBinds = [
    # Toggle the focused group between a tab stack and a plain split.
    {_args = ["SUPER + g" (mkLuaInline ''function() hl.plugin.hy3.change_group("toggletab") end'')];}
    # Cycle tabs within the focused tab group (wraps around).
    {_args = ["SUPER + bracketright" (mkLuaInline ''function() hl.plugin.hy3.focus_tab({ direction = "r", wrap = true }) end'')];}
    {_args = ["SUPER + bracketleft" (mkLuaInline ''function() hl.plugin.hy3.focus_tab({ direction = "l", wrap = true }) end'')];}
    # Expand the focused node over its siblings; Shift+e resets it.
    {_args = ["SUPER + e" (mkLuaInline ''function() hl.plugin.hy3.expand("expand") end'')];}
    {_args = ["SUPER + SHIFT + e" (mkLuaInline ''function() hl.plugin.hy3.expand("base") end'')];}
    # Re-balance every split on the workspace back to equal (workspace scope is
    # required; group scope is a no-op in hy3 0.55 -- see ./common.nix).
    {_args = ["SUPER + SHIFT + equal" (mkLuaInline ''function() hl.plugin.hy3.equalize({ scope = "workspace" }) end'')];}
  ];

  # exec-once -> a single hl.on("hyprland.start", ...) handler. hy3's plugin
  # load is emitted separately by home-manager (from `plugins` below) into its
  # own start hook.
  autostartHook = mkLuaInline ''
    function()
      hl.exec_cmd(${luaStr waybarLaunch})
      hl.exec_cmd("sworkstyle >/tmp/sworkstyle.log 2>&1")
      hl.exec_cmd(${luaStr "${lib.getExe pkgs.activate-linux} -t \"Activate NixOS\" -m \"Edit configuration.nix to activate NixOS.\" -x 360 -c \"1-1-1-0.10\""})
      hl.exec_cmd("[workspace 1 silent] kitty")
      hl.exec_cmd(${luaStr "[workspace 2 silent] ${firefox}"})
      hl.exec_cmd(${luaStr "[workspace 3 silent] ${firefox} --private-window google.com"})
      hl.exec_cmd("[workspace 3 silent] legcord")
      hl.exec_cmd("[workspace 3 silent] keepassxc")
      hl.exec_cmd("[workspace 3 silent] telegram")
    end
  '';

  # hl.env("KEY", "VALUE") -- split "KEY,VALUE" (value may itself contain commas,
  # e.g. GDK_BACKEND,wayland,x11).
  toEnv = e: let
    p = lib.splitString "," e;
  in {
    _args = [(lib.head p) (lib.concatStringsSep "," (lib.tail p))];
  };

  # A resize-submap bind: hl.bind("<key>", <dispatcher>, <opts>).
  submapBind = key: dispatcher: opts: {
    _args = ["${key}" (mkLuaInline dispatcher)] ++ lib.optional (opts != {}) opts;
  };
in {
  config = {
    wayland = {
      windowManager.hyprland = {
        enable = true;
        package = pkgs.latest.hyprland;
        configType = "lua";

        # hy3: i3/sway-style manual tiling with tabbed nodes, from nixpkgs'
        # hyprlandPlugins (ABI-matched to pkgs.latest.hyprland). home-manager
        # emits `hyprctl plugin load <path>` in the generated start hook.
        plugins = [pkgs.latest.hy3];
        systemd.enable = false;
        xwayland.enable = true;

        settings = {
          # hl.config({...}) -- all "variable"-style settings nest under one key.
          config = {
            general = {
              layout = "hy3";
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
                # everything else falls back to a lighter 3-pass, no-xray blur.
                passes =
                  if config.gpu.strong.enable
                  then 4
                  else 3;
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

            render = {
              cm_enabled = true;
              cm_auto_hdr = 1;
              cm_sdr_eotf = 0;
            };

            group = {
              "col.border_active" = "rgba(5eead4ee)";
              groupbar = {
                "col.inactive" = "rgba(595959aa)";
                "col.active" = "rgba(595959FF)";
              };
            };

            input = {
              # ~200ms delay (mac InitialKeyRepeat 15), rate 45Hz.
              repeat_rate = 45;
              repeat_delay = 200;
              # accel_profile is global in Hyprland; "adaptive" is the libinput
              # default, so the mouse is unaffected -- this mirrors sway.
              accel_profile = "adaptive";
              # Touchpad parity with sway's type:touchpad block.
              touchpad = {
                natural_scroll = true;
                disable_while_typing = true;
                tap_to_click = true;
                drag_lock = false;
              };
            };

            # TODO(lua): custom beziers/animations deferred. hl.config animations
            # only toggles `enabled`; the curves need hl.curve + hl.animation
            # calls keyed by lua "leaf" names (NOT the hyprlang animation names),
            # which must be confirmed at runtime. Defaults are used for now.
            animations.enabled = true;
          };

          # hl.env("KEY", "VALUE")
          env = map toEnv [
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

          # hl.monitor({...}) -- the sway desc rules split into fields.
          monitor = [
            {output = "desc:LG Display 0x0676"; mode = "1920x1080@60.02"; position = "6400x0"; scale = 1.0;}
            {output = "desc:Shenzhen KTC Technology Group H27S17 0x00000001"; mode = "2560x1440@119.99"; position = "3840x0"; scale = 1.0; bitdepth = 10;}
            {output = "desc:ASUSTek COMPUTER INC VG279 K5LMQS018158"; mode = "1920x1080@119.98"; position = "0x0"; scale = 1.0; bitdepth = 10;}
            {output = "desc:ASUSTek COMPUTER INC VG259QM S1LMQS002054"; mode = "1920x1080@119.88"; position = "1920x0"; scale = 1.0; bitdepth = 10;}
            {output = ""; mode = "preferred"; position = "auto"; scale = 1;}
          ];

          # hl.gesture({...}) -- 3-finger horizontal swipe to switch workspaces.
          gesture = [
            {fingers = 3; direction = "horizontal"; action = "workspace";}
          ];

          # hl.device({...}) -- PS4 controller touchpad override (parity with
          # sway's 1356:2508 rule). Hyprland matches by lowercased, hyphenated
          # libinput name; verify with `hyprctl devices` (a wrong name no-ops).
          device = [
            {
              name = "sony-interactive-entertainment-wireless-controller-touchpad";
              disable_while_typing = false;
              tap_to_click = true;
            }
          ];

          # hl.bind(...) -- generated from swayKeybindings (toLua) + hy3 extras.
          bind = generatedLuaBinds ++ hy3ExtraBinds;

          # hl.on("hyprland.start", function() ... end) -- autostart.
          on = [
            {_args = ["hyprland.start" autostartHook];}
          ];

          # TODO(lua): hy3 plugin config (tabs look + autotile) is NOT set here.
          # hl.config({ plugin = { hy3 = ... } }) fails at parse ("unknown config
          # key plugin.hy3.*") because hy3's keys only register once it loads at
          # startup. It needs a post-load hook (hyprctl keyword plugin:hy3:...)
          # ordered AFTER home-manager's plugin-load start hook. Deferred until
          # the runtime mechanism is confirmed; hy3 uses defaults (no autotile,
          # default tab bar) until then. Old values were:
          #   tabs = { height = 22; padding = 6; render_text = true; text_center = true; };
          #   autotile = { enable = true; ephemeral_groups = true; };
        };

        systemd.variables = ["--all"];

        # Resize submap -- parity with sway's `resize` mode (structured Lua form
        # via hl.define_submap). common.nix's toLua maps Super+r to
        # `hl.dsp.submap("resize")`; this defines that submap. vim hjkl resizes,
        # Shift+hjkl nudges (relative move, floating-friendly), `r` equalizes the
        # workspace, and Escape / Return / Super+r exit. `binde` (repeating) ->
        # the { repeating = true } opt.
        submaps.resize.settings.bind = [
          (submapBind "h" "hl.dsp.window.resize({ x = -10, y = 0, relative = true })" {repeating = true;})
          (submapBind "l" "hl.dsp.window.resize({ x = 10, y = 0, relative = true })" {repeating = true;})
          (submapBind "k" "hl.dsp.window.resize({ x = 0, y = -10, relative = true })" {repeating = true;})
          (submapBind "j" "hl.dsp.window.resize({ x = 0, y = 10, relative = true })" {repeating = true;})
          (submapBind "SHIFT + h" "hl.dsp.window.move({ x = -10, y = 0, relative = true })" {repeating = true;})
          (submapBind "SHIFT + l" "hl.dsp.window.move({ x = 10, y = 0, relative = true })" {repeating = true;})
          (submapBind "SHIFT + k" "hl.dsp.window.move({ x = 0, y = -10, relative = true })" {repeating = true;})
          (submapBind "SHIFT + j" "hl.dsp.window.move({ x = 0, y = 10, relative = true })" {repeating = true;})
          # `r` equalizes the whole workspace back to 50/50 (stays in the submap).
          (submapBind "r" ''function() hl.plugin.hy3.equalize({ scope = "workspace" }) end'' {})
          # Exits.
          (submapBind "escape" "hl.dsp.submap(\"reset\")" {})
          (submapBind "return" "hl.dsp.submap(\"reset\")" {})
          (submapBind "SUPER + r" "hl.dsp.submap(\"reset\")" {})
        ];
      };
    };
  };
}
