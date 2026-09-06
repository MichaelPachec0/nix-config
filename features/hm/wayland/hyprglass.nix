# hyprglass (liquid-glass window decoration): options, plugin setup hook and
# generated window rules.
#
# This module never writes `wayland.windowManager.hyprland.settings` itself:
# that attrset is freeform, so two modules writing `settings.on` (or
# `settings.window_rule`) would collide rather than concatenate, and
# hyprland.nix must stay the single writer of `settings`. Everything here is
# exported through `_module.args.generatedHyprglass` for hyprland.nix to
# splice in: the same seam app-run.nix (appRun) and hypr-wl-debug.nix
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
  # package into its closure: overlays are lazy and the path interpolation is
  # what triggers the build, the same mechanism that keeps pkgs.latest.hy3 out
  # of non-Hyprland closures.
  hyprglassSo = "${pkgs.latest.hyprglass}/lib/libhyprglass.so";

  # Frost tint: theme bgMain (gruvbox bg0_hard) at 0x60 alpha. The alpha is
  # deliberately far above upstream's 0x22: windows sit at 0.9 opacity here, so
  # the tint multiplying into the blurred backdrop is the main channel through
  # which the frost still reads. Shared by stock_tint and current_set: the
  # two presets differ in geometry/tone parameters, not tint.
  tint = "0x${theme.palette.bgMain}60";

  # theme.palette hex -> "r, g, b" for the glass chrome stylesheet.
  rgb = hex: let
    c = i: toString (lib.fromHexString (builtins.substring i 2 hex));
  in "${c 0}, ${c 2}, ${c 4}";

  luaBool = b:
    if b
    then "true"
    else "false";

  # Apps whose colour fidelity must not be touched. One list generates all
  # three rule families (opacity 1.0, no_blur, hyprglass_disabled tag) so they
  # cannot drift apart. Windscribe matches on title rather than class: the
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
  # content. noglass only: their opacity and blur are left alone. Class
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
  # Nix float -> Hyprland number without toString's "0.900000" padding.
  num = builtins.toJSON;

  # Per-app glass entry (hyprglass.apps). Every field maps to one window rule
  # or one plugin tag, so `hyprctl clients -j` shows exactly what applied and
  # any of it can be overridden live with hl.dsp.window.set_prop / tag.
  appModule = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Rule-name suffix.";
      };
      match = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        description = "hl.window_rule match table (class/title are ANCHORED regexes: \"firefox.*\" for firefox-dev).";
      };
      opacity = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule {
          options = {
            active = lib.mkOption {
              type = lib.types.float;
              default = 0.9;
            };
            inactive = lib.mkOption {
              type = lib.types.float;
              default = 0.9;
            };
          };
        });
        default = null;
        description = "Compositor opacity rule; null leaves the global opacity-all rule in force.";
      };
      preset = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "hyprglass preset name (hyprglass_preset_<name> tag); null = default_preset.";
      };
      theme = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum ["dark" "light"]);
        default = null;
        description = "hyprglass theme routing (hyprglass_theme_<t> tag); null = default_theme.";
      };
      mask = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Mask mode: glass only where the app's own pixels are transparent (hyprglass_masked tag).";
      };
      glass = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "false = hyprglass_disabled tag + no_blur, the window renders plain.";
      };
      videoRect = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Honour hyprglass_rect: tags from the playback bridge (dim holes + surface redraw); false = hyprglass_rect_off tag.";
      };
    };
  };

  # hyprglass.apps -> window rules + tags. One rule per effect, in the order
  # opacity, glass-off, mask, preset, theme, rect-off. Opacity entries must
  # splice in AFTER the global opacity-all rule to override it (hyprland.nix
  # honours that by appending these after it).
  appRules = lib.concatMap (app:
    lib.optional (app.opacity != null) {
      name = "opacity-${app.name}";
      inherit (app) match;
      opacity = "${num app.opacity.active} ${num app.opacity.inactive}";
    }
    ++ lib.optionals (!app.glass) [
      {
        name = "noglass-${app.name}";
        inherit (app) match;
        tag = "+hyprglass_disabled";
      }
      {
        name = "noblur-${app.name}";
        inherit (app) match;
        no_blur = true;
      }
    ]
    ++ lib.optional app.mask {
      name = "maskglass-${app.name}";
      inherit (app) match;
      tag = "+hyprglass_masked";
    }
    ++ lib.optional (app.preset != null) {
      name = "preset-${app.name}";
      inherit (app) match;
      tag = "+hyprglass_preset_${app.preset}";
    }
    ++ lib.optional (app.theme != null) {
      name = "theme-${app.name}";
      inherit (app) match;
      tag = "+hyprglass_theme_${app.theme}";
    }
    ++ lib.optional (!app.videoRect) {
      name = "rectoff-${app.name}";
      inherit (app) match;
      tag = "+hyprglass_rect_off";
    })
  config.hyprglass.apps;
in {
  # The bridge options used to live under hyprglass.videoBridge; they are now
  # ffHyprlandBridge.video (features/hm/wayland/ff-hyprland-bridge.nix).
  imports =
    map (name:
      lib.mkRenamedOptionModule ["hyprglass" "videoBridge" name] ["ffHyprlandBridge" "video" name])
    ["playbackAction" "rectFallback" "rectRateHz" "playSignal" "pauseGraceMs"];

  options.hyprglass = {
    # Not mkEnableOption: that hardcodes `default = false`, and the default
    # here reads config: glass is on exactly where the hardware can afford
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
    # blur-quickshell-bar layer rule dropped: see the spec before enabling.
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

    # Per-app glass configuration, the declarative twin of the window rules
    # and tags the plugin reads. Firefox: back in the global 0.9 opacity
    # family so page content is glassy like every other window; the video
    # stays pixel-exact through the rect redraw (hyprglass.rect) while the
    # bridge reports a rect. Mask mode (opacity 1.0 + mask = true) remains
    # one edit away. The PiP toplevel is opaque and glass-free on its own:
    # the extension cannot see into it.
    apps = lib.mkOption {
      type = lib.types.listOf appModule;
      default = [
        {
          name = "firefox";
          match = {class = "firefox.*";};
          opacity = {
            active = 0.9;
            inactive = 0.9;
          };
        }
        {
          name = "firefox-pip";
          match = {
            class = "firefox.*";
            title = "^Picture-in-Picture$";
          };
          opacity = {
            active = 1.0;
            inactive = 1.0;
          };
          glass = false;
          videoRect = false;
        }
      ];
      description = "Per-app opacity/preset/theme/mask/glass/videoRect, expanded to window rules and plugin tags.";
    };

    # Plugin-side rect handling (plugin:hyprglass:rect_*), reloadable through
    # hg.config like xray. Applies to any window carrying hyprglass_rect: tags.
    rect = {
      dim = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Draw the inactive dim with holes at the rects (rect_dim).";
      };
      redraw = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Redraw the window surface inside each rect on top of the translucent window (rect_redraw).";
      };
      redrawAlpha = lib.mkOption {
        type = lib.types.float;
        default = 1.0;
        description = "Alpha of that redraw: 1.0 = video opaque, lower keeps some glass through it (rect_redraw_alpha).";
      };
      padding = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Logical px grown around each rect, hides player edge fringe (rect_padding).";
      };
    };

    # Firefox chrome stylesheet (HM-owned, imported by the profile's own
    # userChrome.css) plus the bridge install.
    firefox = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.hyprglass.enable;
        defaultText = lib.literalExpression "config.hyprglass.enable";
        description = "Ship the glass chrome stylesheet and enable the Firefox to Hyprland bridge.";
      };
      chromeAlpha = lib.mkOption {
        type = lib.types.float;
        default = 0.32;
        description = "Alpha of the toolbox tint; multiplies with the compositor opacity of the firefox apps entry.";
      };
      chromeColor = lib.mkOption {
        type = lib.types.str;
        default = theme.palette.bgMain;
        defaultText = lib.literalExpression "theme.palette.bgMain";
        description = "Toolbox tint colour, 6-digit hex without #.";
      };
      profileDir = lib.mkOption {
        type = lib.types.str;
        default = "cxnb9yr4.dev-edition-default";
        description = "Profile directory under ~/.mozilla/firefox that receives the glass chrome stylesheet.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf config.hyprglass.firefox.enable {
      # Firefox glass chrome. HM manages ONLY this stylesheet; the owner's
      # hand-maintained userChrome.css imports it via a one-line @import at
      # its top (their file backed up as userChrome.css.pre-hyprglass.bak),
      # and their user.js carries browser.tabs.allow_transparent_browser.
      # That split keeps their curated files theirs -- option (b) of the
      # profile-management fork.
      #
      # Window root transparent so alpha reaches the compositor, toolbox
      # tinted at chromeAlpha, bars transparent so the toolbox shade is the
      # single chrome tint. Content area is untouched: pages paint their own
      # backgrounds and the compositor opacity (hyprglass.apps) makes them
      # glassy.
      home.file.".mozilla/firefox/${config.hyprglass.firefox.profileDir}/chrome/hyprglass-glass.css".text = ''
        /* hyprglass glass chrome -- managed by home-manager (hyprglass.nix).
           Edit there, not here. */
        /* body is load-bearing: since the chrome document became HTML the
           opaque window background is painted by <body>, not #main-window.
           Bisected on 156.0b1 with throwaway profiles: without body every
           other rule here leaves the toolbar opaque. */
        #main-window,
        body,
        #browser,
        #tabbrowser-tabpanels {
          background: transparent !important;
        }
        #navigator-toolbox {
          background-color: rgba(${rgb config.hyprglass.firefox.chromeColor}, ${num config.hyprglass.firefox.chromeAlpha}) !important;
          background-image: none !important;
        }
        #nav-bar,
        #toolbar-menubar,
        #PersonalToolbar {
          background-color: transparent !important;
        }
      '';

      # The playback bridge moved to its own module (ffHyprlandBridge); the
      # glass chrome just turns it on.
      ffHyprlandBridge.enable = true;
    })
    {
    # The plugin config, at the TOP LEVEL of the generated hyprland.lua (the
    # hyprland module appends extraConfig verbatim; types.lines merges with
    # hyprland.nix's monitors block). This is the mechanism upstream's Lua
    # support is built around, and the only one that works:
    #
    #   parse 1 (session start): plugin not loaded, hl.plugin.hyprglass is
    #     nil, block skipped.
    #   start hook: hyprctl plugin load. PLUGIN_INIT then calls reloadConfig
    #     synchronously, so:
    #   parse 2: hl.plugin.hyprglass exists, block runs DURING the parse;
    #     hg.preset entries pend and the parse-end config.reloaded commits
    #     them. No timer and no race: however long the async load takes,
    #     the re-parse it triggers is what applies the config.
    #
    # hg.config sets ONLY behavioural keys (theme routing, xray, layers). No
    # aesthetic value may be set as a global: stock_pure is an EMPTY preset
    # precisely so it resolves to pure upstream defaults, which makes it a
    # usable comparison arm against stock_tint and current_set. Lua booleans
    # coerce to Hyprlang ints through hl.config (verified live).
    wayland.windowManager.hyprland.extraConfig = lib.mkIf config.hyprglass.enable ''
      -- hyprglass: runs on the config re-parse the plugin load triggers; the
      -- first parse (plugin absent) skips it. Presets only commit when
      -- registered during a parse, which is why this is not in the start hook.
      if hl.plugin.hyprglass then
        local hg = hl.plugin.hyprglass
        hg.config({
          default_theme = "${theme.meta.mode}",
          default_preset = "current_set",
          xray = ${luaBool config.hyprglass.xray},
          rect_dim = ${luaBool config.hyprglass.rect.dim},
          rect_redraw = ${luaBool config.hyprglass.rect.redraw},
          rect_redraw_alpha = ${num config.hyprglass.rect.redrawAlpha},
          rect_padding = ${toString config.hyprglass.rect.padding},
          layers = { enabled = ${luaBool config.hyprglass.layers.enable} },
        })
        -- Three permanent presets so A/B runs side by side on tagged windows
        -- (hl.dsp.window.tag) instead of sequentially from memory.
        hg.preset("stock_pure", {})
        hg.preset("stock_tint", { tint_color = ${tint} })
        -- current_set: tuned for 0.9-opacity windows. The interior is 90%
        -- occluded by the app's own pixels, so the visible effect lives in
        -- the bezel: wider edge band, less centre-dome distortion, less
        -- spectral fringing on glyph margins, tint as the channel that still
        -- lands. dark.adaptive_dim is readability work: dims bright backdrop
        -- patches so a white page underneath cannot wash out the frost.
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
        -- contrasted: the built-in high_contrast with a stronger dim and a
        -- deep blue dark tint. (The other built-ins: clear, glass, subtle,
        -- high_contrast: are always selectable without registration.)
        hg.preset("contrasted", {
          inherits = "high_contrast",
          contrast = 1.2,
          adaptive_dim = 1.5,
          dark = { tint_color = 0x02142aa9 },
        })
        -- glassy: heavy stylised glass: strong lensing, fringing and
        -- vibrancy pushed high, theme tint.
        hg.preset("glassy", {
          blur_strength = 2.0,
          blur_iterations = 3,
          chromatic_aberration = 0.8,
          fresnel_strength = 0.8,
          edge_thickness = 0.08,
          tint_color = ${tint},
          lens_distortion = 0.9,
          brightness = 1.0,
          contrast = 1.7,
          saturation = 1,
          vibrancy = 0.8,
          vibrancy_darkness = 1,
          adaptive_boost = 0.5,
        })
        -- LightGlass: white-tinted bright glass. NOTE two out-of-range
        -- values kept verbatim from the source config: glass_opacity 1.2
        -- (above the usual 0..1) and edge_thickness 1.18 (an order of
        -- magnitude above the typical 0.03-0.1 band): expect a very wide,
        -- possibly clamped bezel.
        hg.preset("LightGlass", {
          blur_strength = 4,
          blur_iterations = 2,
          lens_distortion = 0.3,
          refraction_strength = 1.0,
          chromatic_aberration = 0.2,
          fresnel_strength = 0.4,
          specular_strength = 0.8,
          glass_opacity = 1.2,
          edge_thickness = 1.18,
          tint_color = 0xFFFFFF22,
          adaptive_dim = 0.2,
        })
        -- terminal_glass: subtle refractive pane tuned for terminals. The
        -- source derived its tint from a pywal scheme background at 0.35
        -- alpha at runtime; here that is the theme bgMain at 0x59 (~0.35).
        hg.preset("terminal_glass", {
          blur_strength = 1.5,
          blur_iterations = 2,
          refraction_strength = 2.2,
          chromatic_aberration = 0.18,
          fresnel_strength = 0.35,
          specular_strength = 0.45,
          glass_opacity = 1.0,
          edge_thickness = 0.03,
          tint_color = 0x${theme.palette.bgMain}59,
          lens_distortion = 0.08,
          brightness = 0.95,
          contrast = 1.12,
          saturation = 0.95,
          vibrancy = 0.35,
          vibrancy_darkness = 0.25,
          adaptive_dim = 0.22,
          adaptive_boost = 0.08,
        })
        -- custom_liquid: ported from an "Evident LiquidGlass" config for the
        -- separate liquidglass plugin; only the keys that exist as hyprglass
        -- preset fields carried over (its enabled/exclude/window_opacity/
        -- layer_* globals have no preset equivalent). Cool blue tint with
        -- alpha 00, i.e. tint disabled but recorded.
        hg.preset("custom_liquid", {
          blur_strength = 0.32,
          blur_iterations = 2,
          refraction_strength = 1.15,
          chromatic_aberration = 0.90,
          lens_distortion = 1.15,
          fresnel_strength = 0.46,
          specular_strength = 0.38,
          edge_thickness = 0.040,
          tint_color = 0xb8d8ff00,
          glass_opacity = 0.78,
          brightness = 0.88,
          contrast = 1.16,
          saturation = 1.14,
          vibrancy = 0.32,
          adaptive_dim = 0.32,
          adaptive_boost = 0.10,
        })
        -- yujon_glass: pure refraction lens: zero blur, zero tint, zero
        -- fringing, full fresnel/specular. Converted from a config that set
        -- these as plugin globals rather than a preset.
        hg.preset("yujon_glass", {
          blur_strength = 0,
          blur_iterations = 1,
          refraction_strength = 2.5,
          chromatic_aberration = 0,
          lens_distortion = 1,
          edge_thickness = 0.018,
          fresnel_strength = 1,
          specular_strength = 1,
          tint_color = 0x00000000,
          glass_opacity = 1,
          brightness = 1,
          contrast = 1.0,
          saturation = 1.0,
          vibrancy = 0.0,
          adaptive_dim = 0.4,
          adaptive_boost = 0.0,
        })
        -- apple: bright rim-lit look: light blur, full fresnel/specular,
        -- opaque glass pane, no adaptive dim.
        hg.preset("apple", {
          blur_strength = 0.8,
          blur_iterations = 2,
          refraction_strength = 0.8,
          chromatic_aberration = 0.6,
          fresnel_strength = 1.0,
          specular_strength = 1.0,
          glass_opacity = 1.0,
          edge_thickness = 0.1,
          lens_distortion = 0.5,
          brightness = 1.1,
          contrast = 1.0,
          saturation = 1.0,
          vibrancy = 0.2,
          vibrancy_darkness = 0.0,
          adaptive_dim = 0.0,
          adaptive_boost = 0.2,
        })
      end
    '';

    _module.args.generatedHyprglass = {
      # ONLY the plugin load. No timer, and deliberately no config here: a
      # timer-applied hg.config/hg.preset is structurally broken, not just
      # racy. Runtime hl.config never fires config.reloaded, and
      # config.preReload wipes the plugin's pending-preset buffer, so presets
      # registered outside a config parse can never commit. The config lives
      # in the extraConfig block below instead, which the load-triggered
      # re-parse executes.
      setupHook = mkLuaInline ''
        function()
          hl.exec_cmd("hyprctl plugin load ${hyprglassSo}")
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

      # hyprglass.apps expanded (see appRules above). Emitted unconditionally
      # like the other families; tags are inert without the plugin.
      inherit appRules;

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
    }
  ];
}
