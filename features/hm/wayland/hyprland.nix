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
  theme,
  generatedLuaBinds,
  generatedSwayBinds,
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

    # Enter the group_with submap (defined under submaps.groupwith below): wrap
    # the focused node TOGETHER with a neighbour into a NEW group. Leader sits
    # next to Super+g (toggletab) -- both are "g for group". `hl.dsp.submap` is a
    # native dispatcher (resolved at parse time), so no function() wrapper.
    {_args = ["SUPER + SHIFT + g" (mkLuaInline ''hl.dsp.submap("groupwith")'')];}
  ];

  # Mouse binds -- sway's `floating_modifier $mod` equivalent (a sway setting,
  # not a keybind, so nothing in swayKeybindings translates it; defined here).
  # Super + left-drag moves the window under the cursor, Super + right-drag
  # resizes it (floating windows move/resize freely; tiled ones resize the
  # split). The Lua config manager has no `bindm`: a mouse bind is a normal bind
  # with { mouse = true; }. drag()/resize() take no args -> the interactive,
  # held-button move/resize (not a one-shot).
  mouseBinds = [
    {_args = ["SUPER + mouse:272" (mkLuaInline "hl.dsp.window.drag()") {mouse = true;}];}
    {_args = ["SUPER + mouse:273" (mkLuaInline "hl.dsp.window.resize()") {mouse = true;}];}
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
              tabs = {
                height = 22,
                padding = 6,
                render_text = true,
                text_center = true,
                text_font = "${theme.fonts.ui}",
                ["col.active"] = "rgba(${theme.palette.accent}ff)",
                ["col.inactive"] = "rgba(${theme.palette.bgItem}ff)",
                ["col.urgent"] = "rgba(${theme.palette.accentRed}ff)",
                ["col.text.active"] = "rgba(${theme.palette.textOnAccent}ff)",
                ["col.text.inactive"] = "rgba(${theme.palette.textPrimary}ff)",
                ["col.text.urgent"] = "rgba(${theme.palette.textOnAccent}ff)",
              },
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
      hl.exec_cmd("qs -c task-bar")
      hl.exec_cmd(${luaStr "${lib.getExe pkgs.activate-linux} -t \"Activate NixOS\" -m \"Edit configuration.nix to activate NixOS.\" -x 360 -c \"1-1-1-0.10\""})
      hl.exec_cmd("[workspace special:magic silent] keepassxc")
      hl.exec_cmd("[workspace special:magic silent] Windscribe")
      hl.exec_cmd("[workspace 3 silent] telegram")
    end
  '';
  # hl.exec_cmd(${luaStr "[workspace 2 silent] ${firefox}"})
  # hl.exec_cmd(${luaStr "[workspace 3 silent] ${firefox} --private-window google.com"})
  # hl.exec_cmd("[workspace 3 silent] legcord")

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

  # ---- Keybind cheatsheet (Super+/) -------------------------------------
  # Rendered with rofi (-dmenu, so it inherits the launcher theme; Esc closes,
  # type to filter). The "Core" rows are DERIVED from generatedSwayBinds -- the
  # same single source the binds themselves come from (common.nix) -- so the
  # sheet can't drift; the hyprland-only hy3 binds and the submaps are curated
  # below. Pure reference: selecting a row does nothing. chDescribe mirrors
  # common.nix's toLuaAction classification, humanised for display.
  chPrettyMods = {
    Mod4 = "Super";
    shift = "Shift";
    Shift = "Shift";
    SHIFT = "Shift";
    alt = "Alt";
    Alt = "Alt";
    ALT = "Alt";
    control = "Ctrl";
    Control = "Ctrl";
    CONTROL = "Ctrl";
    ctrl = "Ctrl";
    Ctrl = "Ctrl";
  };
  chPrettyKeys = {
    minus = "-";
    equal = "=";
    bracketleft = "[";
    bracketright = "]";
    slash = "/";
  };
  chCombo = combo: let
    parts = lib.splitString "+" combo;
    key = lib.last parts;
    mods = lib.init parts;
  in
    lib.concatStringsSep "+" ((map (m: chPrettyMods.${m} or m) mods) ++ [(chPrettyKeys.${key} or key)]);
  chPad = n: s: let
    len = lib.stringLength s;
  in
    s
    + lib.concatStrings (lib.genList (_: " ") (
      if n > len
      then n - len
      else 0
    ));
  chRow = key: desc: "${chPad 24 key}${desc}";
  chDescribe = cmd:
    if lib.hasInfix "grim" cmd
    then "Screenshot region"
    else if lib.hasInfix "swaynag" cmd
    then "Exit session (prompt)"
    else if lib.hasPrefix "exec " cmd
    then
      (let
        toks = lib.splitString " " (lib.removePrefix "exec " cmd);
      in
        builtins.baseNameOf (builtins.head toks)
        + lib.optionalString (builtins.length toks > 1) " ${lib.concatStringsSep " " (builtins.tail toks)}")
    else if cmd == "kill"
    then "Close focused (group-aware)"
    else if cmd == "reload"
    then "Reload config"
    else if cmd == "focus parent"
    then "Focus parent group"
    else if cmd == "focus child"
    then "Focus child node"
    else if lib.hasPrefix "focus " cmd
    then "Focus ${lib.removePrefix "focus " cmd}"
    else if lib.hasPrefix "workspace number " cmd
    then "Workspace ${lib.removePrefix "workspace number " cmd}"
    else if lib.hasPrefix "move container to workspace number " cmd
    then "Move to workspace ${lib.removePrefix "move container to workspace number " cmd}"
    else if cmd == "move scratchpad"
    then "Move to scratchpad"
    else if lib.hasPrefix "move " cmd
    then "Move ${lib.removePrefix "move " cmd}"
    else if cmd == "floating toggle"
    then "Toggle floating"
    else if cmd == "fullscreen toggle"
    then "Toggle fullscreen"
    else if cmd == "scratchpad show"
    then "Show scratchpad"
    else if cmd == "splith"
    then "Split: new horizontal group"
    else if cmd == "splitv"
    then "Split: new vertical group"
    else if cmd == "layout toggle split"
    then "Toggle split orientation"
    else if cmd == "layout stacking"
    then "Tabbed group"
    else if cmd == "layout tabbed"
    then "Tabbed group"
    else if cmd == "mode 'resize'"
    then "Resize mode"
    else cmd;
  chCoreRows = lib.mapAttrsToList (k: v: chRow (chCombo k) (chDescribe v)) generatedSwayBinds;
  cheatText = lib.concatStringsSep "\n" (
    ["KEYBINDS   --   type to filter, Esc to close" "" "-- Core (window manager) --"]
    ++ chCoreRows
    ++ [
      ""
      "-- hy3 groups / focus --"
      (chRow "Super+g" "Toggle tab <-> split")
      (chRow "Super+Shift+b / +v" "Make h / v group (toggle)")
      (chRow "Super+Shift+x / +z" "Make tab group (toggle)")
      (chRow "Super+Shift+t / +u" "Force tab / untab")
      (chRow "Super+a / Super+d" "Focus raise / lower a level")
      (chRow "Super+Shift+a / +d" "Focus outermost / leaf")
      (chRow "Super+e / Shift+e" "Expand focused / reset")
      (chRow "Super+[ / Super+]" "Cycle tab left / right")
      (chRow "Super+Ctrl+f" "Toggle tiled/floating focus")
      (chRow "Super+Shift+=" "Equalize workspace splits")
      (chRow "Super+Shift+Ctrl+hjkl" "Move past neighbour (once)")
      ""
      "-- group_with submap (Super+Shift+g) --"
      (chRow "  hjkl" "Group w/ neighbour -> vertical")
      (chRow "  Shift+hjkl" "Group w/ neighbour -> tabbed")
      (chRow "  Ctrl+hjkl" "Group w/ neighbour -> horizontal")
      (chRow "  Esc / Return" "Cancel")
      ""
      "-- resize submap (Super+r) --"
      (chRow "  hjkl" "Resize")
      (chRow "  Shift+hjkl" "Nudge / move")
      (chRow "  r" "Equalize workspace")
      (chRow "  Esc / Return" "Exit")
      ""
      "-- help --"
      (chRow "Super+/" "This cheatsheet")
    ]
  );
  cheatFile = pkgs.writeText "keybinds-cheatsheet.txt" cheatText;
  # Bare `rofi` (not pkgs.rofi) so it uses the same themed rofi as `menu`.
  cheatsheetScript = pkgs.writeShellScriptBin "keybind-cheatsheet" ''
    exec rofi -dmenu -i -no-custom -p "keybinds" -mesg "Esc to close" < ${cheatFile}
  '';
  cheatBind = {_args = ["SUPER + slash" (mkLuaInline ''hl.dsp.exec_cmd("${cheatsheetScript}/bin/keybind-cheatsheet")'')];};

  # ---- hy3-project: open a project layout on the active workspace ----------
  # Builds T[H[a,{T[b],T[c]}]] -- two kitty shells (cwd=PATH) + a browser; a
  # re-run appends another unit as a sibling root tab (generalises to N).
  # writeShellApplication enforces runtimeInputs on PATH, sets -euo pipefail,
  # and runs shellcheck at build. The standalone hy3-project.sh is read in
  # verbatim (shebang stripped; its bash ${...} are data, not Nix interpolation)
  # and the default browser is injected as an absolute path. runtimeInputs pin
  # only what the script itself runs; kitty/rofi/the browser are launched by the
  # compositor/session (rofi stays the themed one resolved from PATH, and
  # --browser overrides the injected default). See
  # docs/superpowers/plans/2026-06-21-hy3-project-dispatcher-notes.md.
  hy3ProjectScript = pkgs.writeShellApplication {
    name = "hy3-project";
    runtimeInputs = [pkgs.jq pkgs.coreutils pkgs.findutils pkgs.latest.hyprland];
    text = ''
      HY3_PROJECT_DEFAULT_BROWSER=${lib.escapeShellArg firefox}
      export HY3_PROJECT_DEFAULT_BROWSER
      ${lib.concatStringsSep "\n" (lib.tail (lib.splitString "\n" (builtins.readFile ./hy3-project.sh)))}
    '';
  };
  hy3ProjectBind = {_args = ["SUPER + SHIFT + P" (mkLuaInline ''hl.dsp.exec_cmd("${hy3ProjectScript}/bin/hy3-project --pick")'')];};

  # Quickshell Hub toggle. The `global` dispatch fires the GlobalShortcut the
  # shell registers as "quickshell:hubToggle" (quickshell/task-bar/shell.qml).
  # SUPER + Right Alt (Alt_R). NOTE: binding a modifier keysym while another mod
  # is held can be flaky in Hyprland, and Alt_R is ISO_Level3_Shift (AltGr) on
  # some layouts -- if it doesn't fire, rebind to a normal key or use Alt_R's
  # actual keysym for this layout.
  hubBind = {_args = ["SUPER + Alt_R" (mkLuaInline ''hl.dsp.global("quickshell:hubToggle")'')];};

  # ---- hy3-layout: compile the hy3 notation to/from a live layout -----------
  # `hy3-layout build '<notation>'` constructs the layout live; `show` prints the
  # active (or --wk N / --wk all) workspace as notation; --visualize prints an
  # ASCII tree. stdlib-only Python -- only hyprctl is shelled out to (kitty/the
  # browser are launched by the compositor via hl.exec_cmd). Wrapped via
  # writeShellApplication (python3 on the .py) rather than writePython3Bin to
  # skip the build-time flake8 gate. See
  # docs/superpowers/specs/2026-06-22-hy3-layout-design.md.
  hy3LayoutScript = pkgs.writeShellApplication {
    name = "hy3-layout";
    runtimeInputs = [pkgs.python3 pkgs.latest.hyprland];
    text = ''exec python3 ${./hy3_layout.py} "$@"'';
  };
  # NOTE: no keybind yet (deferred). hy3-layout is on PATH via home.packages. To
  # add one later, mirror hy3ProjectBind and append it to the `bind = ...` list
  # -- e.g. a non-destructive "show current layout" notification:
  #   hl.dsp.exec_cmd("sh -c 'notify-send hy3-layout \"$(hy3-layout show --visualize)\"'")
  # or a rofi notation picker that pipes the choice into `hy3-layout build`.

  # hy3-layout-tui: Textual TUI over the engine. Needs the third-party `textual`
  # dep (so python3.withPackages, not the stdlib wrapper) and all four modules
  # importable together -- assemble them into one store dir and run the entry
  # from there so `import hy3_layout*` resolves via sys.path[0]. See
  # docs/superpowers/specs/2026-06-22-hy3-layout-tui-design.md.
  hy3LayoutTuiSrc = pkgs.runCommand "hy3-layout-tui-src" {} ''
    mkdir -p "$out"
    cp ${./hy3_layout.py}           "$out/hy3_layout.py"
    cp ${./hy3_layout_apps.py}      "$out/hy3_layout_apps.py"
    cp ${./hy3_layout_tui_model.py} "$out/hy3_layout_tui_model.py"
    cp ${./hy3_layout_tui.py}       "$out/hy3_layout_tui.py"
  '';
  hy3LayoutTuiPython = pkgs.python3.withPackages (ps: [ps.textual]);
  hy3LayoutTuiScript = pkgs.writeShellApplication {
    name = "hy3-layout-tui";
    runtimeInputs = [hy3LayoutTuiPython pkgs.latest.hyprland];
    text = ''exec python3 ${hy3LayoutTuiSrc}/hy3_layout_tui.py "$@"'';
  };

  # scratchpad-cycle: sway-style cycling scratchpad (special:magic). Super+-
  # (rebound below) reveals the next parked window and hides the previous, one
  # at a time; Super+Shift+- (generated "move scratchpad") parks the focused
  # window. stdlib Python; hyprctl for IPC, notify-send for the empty toast.
  # Pure rotation logic covered by scratchpad_cycle_test.py.
  scratchpadCycleScript = pkgs.writeShellApplication {
    name = "scratchpad-cycle";
    runtimeInputs = [pkgs.python3 pkgs.latest.hyprland pkgs.libnotify];
    text = ''exec python3 ${./scratchpad_cycle.py} "$@"'';
  };
in {
  config = {
    # `keybind-cheatsheet` on PATH so it's runnable from a terminal too (the
    # Super+/ bind invokes it by store path regardless).
    home.packages = [cheatsheetScript hy3ProjectScript hy3LayoutScript hy3LayoutTuiScript scratchpadCycleScript];

    # Keep floating windows that drift on resize pinned in place. Windscribe
    # (Qt, empty app_id) shoves its own window up when the Locations panel
    # expands and never restores it -- Hyprland has no declarative fix, so the
    # keeper daemon (./hypr-window-keeper.nix) re-centers it. Pairs with the
    # scratch-windscribe window_rule below (float + special:magic); the rule
    # parks it, the keeper handles position while it's out of the pad.
    services.hyprWindowKeeper = {
      enable = true;
      rules = [
        {
          match = {title = "^Windscribe$";};
          position = "center";
        }
      ];
    };

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
              gaps_in = 2;
              gaps_out = 4;
              border_size = 2;
              resize_on_border = false;
              allow_tearing = false;
              "col.active_border" = "rgba(${theme.palette.accent}bf)";
              "col.inactive_border" = "rgba(${theme.palette.borderInactive}aa)";
            };

            decoration = {
              rounding = 8;
              active_opacity = 1.0;
              inactive_opacity = 0.9;
              dim_inactive = true;
              dim_strength = 0.18;
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
                enabled = true;
                range = 4;
                render_power = 17;
                color = "rgba(${theme.palette.bgMain}66)"; # active: stronger
                color_inactive = "rgba(${theme.palette.bgMain}22)"; # inactive: recede
              };
            };

            misc = {
              disable_hyprland_logo = true;
              animate_manual_resizes = true;
              enable_swallow = true;
              swallow_regex = "^(kitty)$";
            };

            render = {
              cm_enabled = true;
              cm_auto_hdr = 1;
              cm_sdr_eotf = 0;
            };

            group = {
              # Teal dropped (spec 12.2): group node border now uses the Gruvbox
              # accent. hy3 draws its own tab bar (colored in hy3SetupHook), so the
              # native groupbar greys below are inert under hy3 but kept
              # seam-derived for consistency if the layout ever changes.
              "col.border_active" = "rgba(${theme.palette.accent}ee)";
              groupbar = {
                "col.inactive" = "rgba(${theme.palette.bgItem}ff)";
                "col.active" = "rgba(${theme.palette.accent}ff)";
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
            {
              _args = [
                "md3_standard"
                {
                  type = "bezier";
                  points = [[0.2 0.0] [0.0 1.0]];
                }
              ];
            }
            {
              _args = [
                "md3_decel"
                {
                  type = "bezier";
                  points = [[0.05 0.7] [0.1 1.0]];
                }
              ];
            }
            {
              _args = [
                "md3_accel"
                {
                  type = "bezier";
                  points = [[0.3 0.0] [0.8 0.15]];
                }
              ];
            }
          ];

          # hl.animation({...}) -- per-leaf animations (lua leaf names, verified
          # via --verify-config; "leaf" replaces the hyprlang animation name,
          # "speed" the duration, "style" the trailing style).
          animation = [
            {
              leaf = "windows";
              enabled = true;
              speed = 3;
              bezier = "md3_standard";
              style = "popin 85%";
            }
            {
              leaf = "windowsIn";
              enabled = true;
              speed = 3;
              bezier = "md3_decel";
              style = "popin 85%";
            }
            {
              leaf = "windowsOut";
              enabled = true;
              speed = 3;
              bezier = "md3_accel";
              style = "popin 85%";
            }
            {
              leaf = "windowsMove";
              enabled = true;
              speed = 3;
              bezier = "md3_standard";
              style = "slide";
            }
            {
              leaf = "fade";
              enabled = true;
              speed = 2;
              bezier = "md3_standard";
            }
            {
              leaf = "workspaces";
              enabled = true;
              speed = 3;
              bezier = "md3_decel";
              style = "slidefade 15%";
            }
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
            {
              output = "desc:LG Display 0x0676";
              mode = "1920x1080@60.02";
              position = "6400x0";
              scale = 1.0;
            }
            {
              output = "desc:Shenzhen KTC Technology Group H27S17 0x00000001";
              mode = "2560x1440@119.99";
              position = "3840x0";
              scale = 1.0;
              bitdepth = 10;
            }
            {
              output = "desc:ASUSTek COMPUTER INC VG279 K5LMQS018158";
              mode = "1920x1080@119.98";
              position = "0x0";
              scale = 1.0;
              bitdepth = 10;
            }
            {
              output = "desc:ASUSTek COMPUTER INC VG259QM S1LMQS002054";
              mode = "1920x1080@119.88";
              position = "1920x0";
              scale = 1.0;
              bitdepth = 10;
            }
            {
              output = "";
              mode = "preferred";
              position = "auto";
              scale = 1;
            }
          ];

          # hl.gesture({...}) -- 3-finger horizontal swipe to switch workspaces.
          gesture = [
            {
              fingers = 3;
              direction = "horizontal";
              action = "workspace";
            }
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

          # hl.bind(...) -- generated from swayKeybindings (toLua) + hy3 extras
          # + the Super+/ cheatsheet bind.
          # Super+- normally maps (via toLua) to toggle_special("magic"); drop
          # that generated bind and rebind Super+- to the cycling scratchpad.
          # Super+Shift+- ("move scratchpad" -> special:magic) stays generated.
          # Super+Ctrl+- resets: send the pulled-out member back to the pad.
          bind =
            (builtins.filter (b: (builtins.elemAt b._args 0) != "SUPER + minus") generatedLuaBinds)
            ++ hy3ExtraBinds
            ++ mouseBinds
            ++ [
              {_args = ["SUPER + minus" (mkLuaInline ''hl.dsp.exec_cmd("${scratchpadCycleScript}/bin/scratchpad-cycle")'')];}
              {_args = ["SUPER + CONTROL + minus" (mkLuaInline ''hl.dsp.exec_cmd("${scratchpadCycleScript}/bin/scratchpad-cycle reset")'')];}
              cheatBind
              hy3ProjectBind
              hubBind
            ];

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
            {
              name = "float-ff-share";
              match = {title = "Firefox.*Sharing Indicator";};
              float = true;
              no_focus = true;
            }
            {
              name = "float-pip";
              match = {title = "Picture-in-Picture";};
              float = true;
            }
            {
              name = "float-ff-dropdown";
              match = {title = "Dropdown";};
              float = true;
            }
            {
              name = "float-ff-about";
              match = {title = "^About.*[Ff]irefox.*$";};
              float = true;
            }
            {
              name = "float-complete-install";
              match = {title = "^Complete Installation$";};
              float = true;
            }
            {
              name = "float-steam-news";
              match = {title = "^Steam - News";};
              float = true;
            }
            {
              name = "float-steam-update";
              match = {title = "^Steam - Update";};
              float = true;
            }
            {
              name = "float-steam-selfupd";
              match = {title = "^Steam - Self Updater$";};
              float = true;
            }
            {
              name = "float-steam-guard";
              match = {title = "^Steam Guard";};
              float = true;
            }
            {
              name = "float-zoom";
              match = {title = "^zoom$";};
              float = true;
            }

            # -- Floating (class / app_id -> Hyprland class) --
            {
              name = "float-keepassxc";
              match = {class = "^org.keepassxc.KeePassXC$";};
              center = true;
              float = true;
              size = "800 600";
              workspace = "special:magic"; # park in the cycling scratchpad
            }
            {
              name = "float-mpv";
              match = {class = "^Mpv$";};
              float = true;
            }
            {
              name = "float-pavucontrol";
              match = {class = "[Pp]avucontrol";};
              float = true;
            }
            {
              name = "float-launcher";
              match = {class = "launcher";};
              float = true;
            }
            {
              name = "float-nm-editor";
              match = {class = "^nm-connection-editor$";};
              float = true;
            }
            {
              name = "float-ibus";
              match = {class = "Ibus-ui-gtk3";};
              float = true;
            }
            {
              name = "float-pinentry";
              match = {class = "Pinentry";};
              float = true;
            }
            {
              name = "float-force-float";
              match = {class = ".*force_float.*";};
              float = true;
            }
            {
              name = "float-zenity";
              match = {class = "zenity";};
              float = true;
            }
            {
              name = "float-floating-update";
              match = {class = "floating_update";};
              float = true;
            }
            # Windscribe VPN mini-window + scratchpad. Matched by TITLE --
            # Windscribe is a Qt app that sets no Wayland app_id (empty class),
            # so a class rule never fires; title is the only reliable key.
            # Fixed 350x240 mini-window, no border/rounding, tearing on; floated
            # so it never tiles when cycled onto a workspace, and parked in the
            # cycling scratchpad (special:magic). Centering while it's out of the
            # pad is handled live by hypr-window-keeper -- Windscribe shoves its
            # own window up when the Locations panel expands, and app-driven
            # resizes emit no rule event. Opacity 1.0 lives in the
            # opacity-exceptions block below (must beat opacity-all).
            {
              name = "scratch-windscribe";
              match = {title = "^Windscribe$";};
              float = true;
              size = "350 240";
              min_size = "1 1";
              border_size = 0;
              rounding = 0;
              immediate = true;
              workspace = "special:magic";
            }

            # -- Floating (Anki child windows: class + title) --
            {
              name = "float-anki-profiles";
              match = {
                class = "Anki";
                title = "Profiles";
              };
              float = true;
            }
            {
              name = "float-anki-add";
              match = {
                class = "Anki";
                title = "Add";
              };
              float = true;
            }
            {
              name = "float-anki-browse";
              match = {
                class = "Anki";
                title = "^Browse.*";
              };
              float = true;
            }

            # -- Opacity (sway "for_window opacity set"). The global 0.9 mirrors
            # sway's translucency; drop it if you prefer opaque windows on
            # Hyprland (the decoration block above keeps active/inactive at 1.0).
            # Per-app 1.0 exceptions must follow the global rule to override it.
            {
              name = "opacity-all";
              match = {class = ".*";};
              opacity = "0.9 0.9";
            }
            {
              name = "opacity-gimp";
              match = {class = "[Gg]imp";};
              opacity = "1.0 1.0";
            }
            {
              name = "opacity-krita";
              match = {class = "[Kk]rita";};
              opacity = "1.0 1.0";
            }
            {
              name = "opacity-inkscape";
              match = {class = "org.inkscape.Inkscape";};
              opacity = "1.0 1.0";
            }
            {
              name = "opacity-virt-manager";
              match = {class = "virt-manager";};
              opacity = "1.0 1.0";
            }
            {
              name = "opacity-obs";
              match = {class = "com.obsproject.Studio";};
              opacity = "1.0 1.0";
            }
            {
              name = "opacity-windscribe";
              match = {title = "^Windscribe$";};
              opacity = "1.0 1.0";
            }

            # -- Blur exceptions (sway "for_window blur disable") --
            {
              name = "noblur-gimp";
              match = {class = "[Gg]imp";};
              no_blur = true;
            }
            {
              name = "noblur-krita";
              match = {class = "[Kk]rita";};
              no_blur = true;
            }
            {
              name = "noblur-inkscape";
              match = {class = "org.inkscape.Inkscape";};
              no_blur = true;
            }
            {
              name = "noblur-virt-manager";
              match = {class = "virt-manager";};
              no_blur = true;
            }
            {
              name = "noblur-obs";
              match = {class = "com.obsproject.Studio";};
              no_blur = true;
            }
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

        # group_with submap (hy3 0002 patch) -- entered via Super+Shift+g. Wraps
        # the focused node TOGETHER with its neighbour in <dir> into a NEW group,
        # adding one nesting level. This is the retrofit make_group (wraps one
        # node) and movewindow (flattens into an existing group) can't do.
        # Direction = vim hjkl; the new group's layout is chosen by modifier:
        #   bare h/j/k/l    -> vertical  (stack the pair)
        #   SHIFT  h/j/k/l  -> tabbed    (tab the pair together)
        #   CONTROL h/j/k/l -> horizontal (side-by-side, nested as a unit)
        # Each bind performs the group then exits the submap; Escape/Return and
        # the Super+Shift+g leader also exit. Waybar's hyprland/submap module
        # surfaces "groupwith mode" while active (parity with sway's resize mode).
        # Invocation: hy3 fns return a Lua CLOSURE, so group_with(...) is called
        # with a trailing (). The submap reset is an hl.dsp dispatcher OBJECT,
        # which CANNOT be called directly ("dispatcher objects cannot be called
        # directly; use hl.dispatch(dispatcher)") -- so it goes through
        # hl.dispatch(), NOT a trailing (). Arg shapes (dir, layout) verified
        # live against the patched plugin (see hy3-groupwith memory note).
        submaps.groupwith.settings.bind = let
          gw = dir: layout: ''function() hl.plugin.hy3.group_with("${dir}", "${layout}")(); hl.dispatch(hl.dsp.submap("reset")) end'';
        in [
          # Vertical (bare).
          (submapBind "h" (gw "l" "v") {})
          (submapBind "j" (gw "d" "v") {})
          (submapBind "k" (gw "u" "v") {})
          (submapBind "l" (gw "r" "v") {})
          # Tabbed (Shift).
          (submapBind "SHIFT + h" (gw "l" "tab") {})
          (submapBind "SHIFT + j" (gw "d" "tab") {})
          (submapBind "SHIFT + k" (gw "u" "tab") {})
          (submapBind "SHIFT + l" (gw "r" "tab") {})
          # Horizontal (Control).
          (submapBind "CONTROL + h" (gw "l" "h") {})
          (submapBind "CONTROL + j" (gw "d" "h") {})
          (submapBind "CONTROL + k" (gw "u" "h") {})
          (submapBind "CONTROL + l" (gw "r" "h") {})
          # Exits.
          (submapBind "escape" "hl.dsp.submap(\"reset\")" {})
          (submapBind "return" "hl.dsp.submap(\"reset\")" {})
          (submapBind "SUPER + SHIFT + g" "hl.dsp.submap(\"reset\")" {})
        ];
      };
    };
  };
}
