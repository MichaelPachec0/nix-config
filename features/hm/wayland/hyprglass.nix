# hyprglass (liquid-glass window decoration) -- options, plugin setup hook and
# generated window rules.
#
# This module never writes `wayland.windowManager.hyprland.settings` itself:
# that attrset is freeform, so two modules writing `settings.on` (or
# `settings.window_rule`) would collide rather than concatenate, and
# hyprland.nix must stay the single writer of `settings`. Everything here is
# exported through `_module.args.generatedHyprglass` for hyprland.nix to
# splice in -- the same seam app-run.nix (appRun) and hypr-wl-debug.nix
# (qsBarLaunch) already use.
#
# The arg is named generatedHyprglass, NOT hyprglass: a module arg sharing the
# option namespace's name would shadow `config.hyprglass` in hyprland.nix.
{
  config,
  lib,
  pkgs,
  theme,
  ...
}: let
  inherit (lib.generators) mkLuaInline;

  # The plugin binary. pkgs.latest.hyprglass is vendored in helpers/overlays.nix
  # (upstream v0.7.0 plus the xray patch) and built against the patched
  # compositor. This string is only forced when hyprland.nix actually splices
  # the hook (gated on hyprglass.enable), so a disabled host never pulls the
  # package into its closure -- overlays are lazy and the path interpolation is
  # what triggers the build, the same mechanism that keeps pkgs.latest.hy3 out
  # of non-Hyprland closures.
  hyprglassSo = "${pkgs.latest.hyprglass}/lib/libhyprglass.so";

  # Frost tint: theme bgMain (gruvbox bg0_hard) at 0x60 alpha. The alpha is
  # deliberately far above upstream's 0x22: windows sit at 0.9 opacity here, so
  # the tint multiplying into the blurred backdrop is the main channel through
  # which the frost still reads. Shared by stock_tint and current_set -- the
  # two presets differ in geometry/tone parameters, not tint.
  tint = "0x${theme.palette.bgMain}60";

  luaBool = b:
    if b
    then "true"
    else "false";

  # Apps whose colour fidelity must not be touched. One list generates all
  # three rule families (opacity 1.0, no_blur, hyprglass_disabled tag) so they
  # cannot drift apart. Windscribe matches on title rather than class -- the
  # client's class is unstable across its Qt wrapper versions.
  colorCritical = [
    {
      name = "gimp";
      match = {class = "[Gg]imp";};
    }
    {
      name = "krita";
      match = {class = "[Kk]rita";};
    }
    {
      name = "inkscape";
      match = {class = "org.inkscape.Inkscape";};
    }
    {
      name = "virt-manager";
      match = {class = "virt-manager";};
    }
    {
      name = "obs";
      match = {class = "com.obsproject.Studio";};
    }
    {
      name = "windscribe";
      match = {title = "^Windscribe$";};
    }
  ];

  # Windows that are expensive or pointless to glass: opaque full-motion
  # content. noglass only -- their opacity and blur are left alone. Class
  # matching is unanchored regex, so "steam" also covers every
  # steam_app_<appid> window. Games launched from lutris/heroic carry the game
  # binary's own class and cannot be enumerated; they fall through to the
  # fullscreen rule below.
  glassOptOut = [
    {
      name = "mpv";
      match = {class = "mpv";};
    }
    {
      name = "gamescope";
      match = {class = "gamescope";};
    }
    {
      name = "steam";
      match = {class = "steam";};
    }
    {
      name = "lutris";
      match = {class = "net.lutris.Lutris";};
    }
    {
      name = "heroic";
      match = {class = "heroic";};
    }
  ];
in {
  options.hyprglass = {
    # Not mkEnableOption: that hardcodes `default = false`, and the default
    # here reads config -- glass is on exactly where the hardware can afford
    # it (thanatos is the only gpu.strong host).
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.gpu.strong.enable;
      defaultText = lib.literalExpression "config.gpu.strong.enable";
      description = "Load the hyprglass plugin and apply the glass presets.";
    };

    # The xray patch: glass samples a windowless per-monitor capture instead
    # of the live framebuffer, so a window's backdrop is the wallpaper rather
    # than the window stack beneath it and window motion stops invalidating
    # other windows' glass. Default false to match the patched plugin's own
    # default (xray changes what the effect SHOWS, not only what it costs);
    # hyprland.nix opts this config in explicitly.
    xray = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Sample a windowless background capture (plugin:hyprglass:xray).";
    };

    # Layer-surface glass (the quickshell bar) is phase 2: it rides
    # renderLayer, a private compositor internal upstream warns can break on
    # updates. Flipping this also needs an hg.layer() registration and the
    # blur-quickshell-bar layer rule dropped -- see the spec before enabling.
    layers.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable hyprglass on layer surfaces (phase 2, off).";
    };

    # A fullscreen window is the largest possible sampling area and
    # simultaneously the case where all of the glass is occluded: the worst
    # cost-to-benefit ratio the plugin can hit on this hardware.
    disableOnFullscreen = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Tag fullscreen windows hyprglass_disabled.";
    };
  };

  config = {
    _module.args.generatedHyprglass = {
      # Mirrors hy3SetupHook: async `hyprctl plugin load`, then a oneshot
      # timer applying the config once the plugin's keys exist. The guard is a
      # nil check on hl.plugin.hyprglass -- the plugin registers its own
      # callable table rather than writing into the global config tree.
      #
      # hg.config sets ONLY behavioural keys (theme routing, xray, layers).
      # No aesthetic value may be set as a global: stock_pure is an EMPTY
      # preset precisely so it resolves to pure upstream defaults, which makes
      # it a usable comparison arm against stock_tint and current_set.
      # Lua booleans coerce to Hyprlang ints through hl.config (verified
      # live), so the boolean spellings below are fine.
      setupHook = mkLuaInline ''
        function()
          hl.exec_cmd("hyprctl plugin load ${hyprglassSo}")
          hl.timer(function()
            if hl.plugin.hyprglass then
              local hg = hl.plugin.hyprglass
              hg.config({
                default_theme = "${theme.meta.mode}",
                default_preset = "current_set",
                xray = ${luaBool config.hyprglass.xray},
                layers = { enabled = ${luaBool config.hyprglass.layers.enable} },
              })
              -- Three permanent presets so A/B runs side by side on tagged
              -- windows (hl.dsp.window.tag) instead of sequentially from
              -- memory. stock_pure = upstream defaults, stock_tint = tint
              -- only, current_set = the shipped look.
              hg.preset("stock_pure", {})
              hg.preset("stock_tint", { tint_color = ${tint} })
              -- current_set: tuned for 0.9-opacity windows. The interior is
              -- 90% occluded by the app's own pixels, so the visible effect
              -- lives in the bezel: wider edge band, less centre-dome
              -- distortion, less spectral fringing on glyph margins, tint as
              -- the channel that still lands. dark.adaptive_dim is
              -- readability work: dims bright backdrop patches so a white
              -- page underneath cannot wash out the frost.
              hg.preset("current_set", {
                tint_color = ${tint},
                edge_thickness = 0.09,
                lens_distortion = 0.2,
                chromatic_aberration = 0.35,
                refraction_strength = 0.7,
                specular_strength = 0.7,
                blur_strength = 2.5,
                dark = {
                  brightness = 0.75,
                  adaptive_dim = 0.5,
                },
              })
            end
          end, { type = "oneshot", timeout = 1000 })
        end
      '';

      # colorCritical expanded to its three families. Emitted UNCONDITIONALLY
      # (not gated on hyprglass.enable): a hyprglass_disabled tag is inert
      # when no plugin reads it, and identical rule lists keep nyx and
      # thanatos from drifting apart. Ordering constraint inherited from
      # hyprland.nix: the opacity 1.0 exceptions must FOLLOW the global
      # opacity-all rule to override it, so this list splices in after it.
      colorCriticalRules =
        map (app: {
          name = "opacity-${app.name}";
          inherit (app) match;
          opacity = "1.0 1.0";
        })
        colorCritical
        ++ map (app: {
          name = "noblur-${app.name}";
          inherit (app) match;
          no_blur = true;
        })
        colorCritical
        ++ map (app: {
          name = "noglass-${app.name}";
          inherit (app) match;
          tag = "+hyprglass_disabled";
        })
        colorCritical;

      # glassOptOut expands to noglass only, plus the fullscreen rule.
      # `fullscreen = true` verified accepted by 0.56.2's hl.window_rule.
      glassOptOutRules =
        map (app: {
          name = "noglass-${app.name}";
          inherit (app) match;
          tag = "+hyprglass_disabled";
        })
        glassOptOut
        ++ lib.optional config.hyprglass.disableOnFullscreen {
          name = "noglass-fullscreen";
          match = {fullscreen = true;};
          tag = "+hyprglass_disabled";
        };
    };
  };
}
