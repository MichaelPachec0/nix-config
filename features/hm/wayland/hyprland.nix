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
  # Wrapped in `function() ...() end`: hl.plugin.hy3.* is nil at config-parse
  # time (registers only after the plugin loads at startup), and hl.plugin.hy3.fn
  # RETURNS a dispatcher closure that the trailing () must invoke -- without it
  # the bind is a silent no-op. Arg shapes verified against hy3 src/dispatchers.cpp.
  hy3ExtraBinds = [
    # Toggle the focused group between a tab stack and a plain split.
    {_args = ["SUPER + g" (mkLuaInline ''function() hl.plugin.hy3.change_group("toggletab")() end'')];}
    # Toggle variants of the (non-toggle) Super+b/v/x/z make_group binds: create
    # the group, or dissolve it when the focused node is the sole child of a
    # group of that layout (with 2+ windows it nests instead).
    {_args = ["SUPER + SHIFT + b" (mkLuaInline ''function() hl.plugin.hy3.make_group("h", { toggle = true })() end'')];}
    {_args = ["SUPER + SHIFT + v" (mkLuaInline ''function() hl.plugin.hy3.make_group("v", { toggle = true })() end'')];}
    {_args = ["SUPER + SHIFT + x" (mkLuaInline ''function() hl.plugin.hy3.make_group("tab", { toggle = true })() end'')];}
    {_args = ["SUPER + SHIFT + z" (mkLuaInline ''function() hl.plugin.hy3.make_group("tab", { toggle = true })() end'')];}

    # Explicit (non-toggle) force the focused window's group to tabbed / untabbed.
    {_args = ["SUPER + SHIFT + t" (mkLuaInline ''function() hl.plugin.hy3.change_group("tab")() end'')];}
    {_args = ["SUPER + SHIFT + u" (mkLuaInline ''function() hl.plugin.hy3.change_group("untab")() end'')];}
    # Toggle focus between the tiled and floating layers (default warps cursor).
    {_args = ["SUPER + CONTROL + f" (mkLuaInline ''function() hl.plugin.hy3.toggle_focus_layer()() end'')];}
    # Select all the way up (outermost group) / drop all the way back to the
    # leaf window. Shift variants of Super+a/Super+d (raise/lower one level).
    {_args = ["SUPER + SHIFT + a" (mkLuaInline ''function() hl.plugin.hy3.change_focus("top")() end'')];}
    {_args = ["SUPER + SHIFT + d" (mkLuaInline ''function() hl.plugin.hy3.change_focus("bottom")() end'')];}
    # Cycle tabs within the focused tab group (wraps around).
    {_args = ["SUPER + bracketright" (mkLuaInline ''function() hl.plugin.hy3.focus_tab({ direction = "r", wrap = true })() end'')];}
    {_args = ["SUPER + bracketleft" (mkLuaInline ''function() hl.plugin.hy3.focus_tab({ direction = "l", wrap = true })() end'')];}
    # Expand the focused node over its siblings; Shift+e resets it.
    {_args = ["SUPER + e" (mkLuaInline ''function() hl.plugin.hy3.expand("expand")() end'')];}
    {_args = ["SUPER + SHIFT + e" (mkLuaInline ''function() hl.plugin.hy3.expand("base")() end'')];}
    # Re-balance every split on the workspace back to equal (workspace scope is
    # required; group scope is a no-op in hy3 0.55 -- see ./common.nix).
    {_args = ["SUPER + SHIFT + equal" (mkLuaInline ''function() hl.plugin.hy3.equalize({ scope = "workspace" })() end'')];}

    # Move a window to the NEIGHBOUR group only, without descending into its
    # subgroups (hy3 movewindow `once`). Plain Super+Shift+hjkl (generated)
    # moves into/out of groups directionally, diving into nested groups; this
    # "once" variant keeps the move at the top level -- useful for shuffling a
    # window past a group instead of getting pulled inside it.
    {_args = ["SUPER + SHIFT + CONTROL + h" (mkLuaInline ''function() hl.plugin.hy3.move_window("l", { once = true })() end'')];}
    {_args = ["SUPER + SHIFT + CONTROL + l" (mkLuaInline ''function() hl.plugin.hy3.move_window("r", { once = true })() end'')];}
    {_args = ["SUPER + SHIFT + CONTROL + k" (mkLuaInline ''function() hl.plugin.hy3.move_window("u", { once = true })() end'')];}
    {_args = ["SUPER + SHIFT + CONTROL + j" (mkLuaInline ''function() hl.plugin.hy3.move_window("d", { once = true })() end'')];}
  ];

  # hy3 plugin setup at startup. Two constraints:
  #  - hy3's config keys (plugin:hy3:*) only register once the plugin loads, so
  #    they can't be set at config-parse time ("unknown config key").
  #  - `hyprctl keyword` is REJECTED under the Lua manager ("use eval"), so the
  #    config must be applied with hl.config, not hyprctl keyword.
  # hl.config DOES work at runtime once the keys are registered. So: load hy3
  # (async, via hyprctl plugin load) and defer hl.config to a one-shot timer
  # that fires after the load completes. general.layout = "hy3" is set in
  # settings.config below, so no re-assert is needed here.
  hy3so = "${pkgs.latest.hy3}/lib/libhy3.so";
  hy3SetupHook = mkLuaInline ''
    function()
      hl.exec_cmd("hyprctl plugin load ${hy3so}")
      hl.timer(function()
        hl.config({
          plugin = {
            hy3 = {
              tabs = { height = 22, padding = 6, render_text = true, text_center = true },
              autotile = { enable = true, ephemeral_groups = true },
            },
          },
        })
      end, { type = "oneshot", timeout = 1000 })
    end
  '';

  # exec-once -> a single hl.on("hyprland.start", ...) handler.
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

        # hy3 (i3/sway-style manual tiling, from nixpkgs' hyprlandPlugins,
        # ABI-matched to pkgs.latest.hyprland) is loaded + configured via the
        # hy3SetupHook start hook below, NOT home-manager's `plugins` -- the
        # plugin's config keys must be applied in the same ordered command as
        # the load (see hy3SetupHook). pkgs.latest.hy3 stays in the closure via
        # the hy3so path reference.
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

            # hl.config animations only toggles `enabled`; the curves and
            # per-leaf animations are separate hl.curve / hl.animation calls
            # (settings.curve / settings.animation below).
            animations.enabled = true;
          };

          # hl.curve(name, {...}) -- bezier curves referenced by the animations.
          curve = [
            {_args = ["easeOutQuint" {type = "bezier"; points = [[0.22 1] [0.36 1]];}];}
            {_args = ["easeInQuart" {type = "bezier"; points = [[0.89 0.03] [0.68 0.19]];}];}
            {_args = ["softLinear" {type = "bezier"; points = [[0.1 0.1] [1 1]];}];}
          ];

          # hl.animation({...}) -- per-leaf animations (lua leaf names, verified
          # via --verify-config; "leaf" replaces the hyprlang animation name,
          # "speed" the duration, "style" the trailing style).
          animation = [
            {leaf = "windows"; enabled = true; speed = 3; bezier = "easeOutQuint"; style = "popin 90%";}
            {leaf = "windowsIn"; enabled = true; speed = 3; bezier = "easeOutQuint"; style = "popin 90%";}
            {leaf = "windowsOut"; enabled = true; speed = 2; bezier = "easeInQuart"; style = "popin 95%";}
            {leaf = "windowsMove"; enabled = true; speed = 3; bezier = "easeOutQuint"; style = "slide";}
            {leaf = "fade"; enabled = true; speed = 3; bezier = "softLinear";}
            {leaf = "workspaces"; enabled = true; speed = 4; bezier = "easeOutQuint"; style = "slidefade 20%";}
          ];

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

          # hl.on("hyprland.start", function() ... end). hy3 setup runs first
          # (load + config), then the autostart apps.
          on = [
            {_args = ["hyprland.start" hy3SetupHook];}
            {_args = ["hyprland.start" autostartHook];}
          ];

          # hl.window_rule({...}) -- parity with sway's floating.criteria, the
          # Firefox-share nofocus, and the opacity/blur for_window rules (#3).
          #
          # CAVEAT: `match.class` is Hyprland's class, which differs from sway's
          # X11 `class` for Wayland-native apps. These strings are a faithful
          # port of the sway values; verify each against `hyprctl clients -j`
          # with the app open and adjust as needed (a wrong match just no-ops).
          #
          # NOT ported (no Hyprland equivalent): sway's window_role (pop-up,
          # bubble, task_dialog, Preferences) and window_type (dialog, menu)
          # float criteria -- Hyprland has no role/type match.
          window_rule = [
            # -- Floating (title) --
            {name = "float-ff-share"; match = {title = "Firefox.*Sharing Indicator";}; float = true; no_focus = true;}
            {name = "float-pip"; match = {title = "Picture-in-Picture";}; float = true;}
            {name = "float-ff-dropdown"; match = {title = "Dropdown";}; float = true;}
            {name = "float-ff-about"; match = {title = "^About Mozilla Firefox$";}; float = true;}
            {name = "float-complete-install"; match = {title = "^Complete Installation$";}; float = true;}
            {name = "float-steam-news"; match = {title = "^Steam - News";}; float = true;}
            {name = "float-steam-update"; match = {title = "^Steam - Update";}; float = true;}
            {name = "float-steam-selfupd"; match = {title = "^Steam - Self Updater$";}; float = true;}
            {name = "float-steam-guard"; match = {title = "^Steam Guard";}; float = true;}
            {name = "float-zoom"; match = {title = "^zoom$";}; float = true;}

            # -- Floating (class / app_id -> Hyprland class) --
            {name = "float-keepassxc"; match = {class = "^KeePassXC$";}; float = true;}
            {name = "float-mpv"; match = {class = "^Mpv$";}; float = true;}
            {name = "float-pavucontrol"; match = {class = "[Pp]avucontrol";}; float = true;}
            {name = "float-launcher"; match = {class = "launcher";}; float = true;}
            {name = "float-nm-editor"; match = {class = "^nm-connection-editor$";}; float = true;}
            {name = "float-ibus"; match = {class = "Ibus-ui-gtk3";}; float = true;}
            {name = "float-pinentry"; match = {class = "Pinentry";}; float = true;}
            {name = "float-force-float"; match = {class = ".*force_float.*";}; float = true;}
            {name = "float-zenity"; match = {class = "zenity";}; float = true;}
            {name = "float-floating-update"; match = {class = "floating_update";}; float = true;}

            # -- Floating (Anki child windows: class + title) --
            {name = "float-anki-profiles"; match = {class = "Anki"; title = "Profiles";}; float = true;}
            {name = "float-anki-add"; match = {class = "Anki"; title = "Add";}; float = true;}
            {name = "float-anki-browse"; match = {class = "Anki"; title = "^Browse.*";}; float = true;}

            # -- Opacity (sway "for_window opacity set"). The global 0.9 mirrors
            # sway's translucency; drop it if you prefer opaque windows on
            # Hyprland (the decoration block above keeps active/inactive at 1.0).
            # Per-app 1.0 exceptions must follow the global rule to override it.
            {name = "opacity-all"; match = {class = ".*";}; opacity = "0.9 0.9";}
            {name = "opacity-gimp"; match = {class = "[Gg]imp";}; opacity = "1.0 1.0";}
            {name = "opacity-krita"; match = {class = "[Kk]rita";}; opacity = "1.0 1.0";}
            {name = "opacity-inkscape"; match = {class = "org.inkscape.Inkscape";}; opacity = "1.0 1.0";}
            {name = "opacity-virt-manager"; match = {class = "virt-manager";}; opacity = "1.0 1.0";}
            {name = "opacity-obs"; match = {class = "com.obsproject.Studio";}; opacity = "1.0 1.0";}

            # -- Blur exceptions (sway "for_window blur disable") --
            {name = "noblur-gimp"; match = {class = "[Gg]imp";}; no_blur = true;}
            {name = "noblur-krita"; match = {class = "[Kk]rita";}; no_blur = true;}
            {name = "noblur-inkscape"; match = {class = "org.inkscape.Inkscape";}; no_blur = true;}
            {name = "noblur-virt-manager"; match = {class = "virt-manager";}; no_blur = true;}
            {name = "noblur-obs"; match = {class = "com.obsproject.Studio";}; no_blur = true;}
          ];

          # hy3 plugin config (tabs look + autotile) is applied at startup by
          # hy3SetupHook (see the let block) -- it can't be set via hl.config at
          # parse time because hy3's keys only register once the plugin loads.
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
          (submapBind "r" ''function() hl.plugin.hy3.equalize({ scope = "workspace" })() end'' {})
          # Exits.
          (submapBind "escape" "hl.dsp.submap(\"reset\")" {})
          (submapBind "return" "hl.dsp.submap(\"reset\")" {})
          (submapBind "SUPER + r" "hl.dsp.submap(\"reset\")" {})
        ];
      };
    };
  };
}
