#⋅kitty-scrollback.nvim⋅Kitten⋅alias↴
# action_alias⋅kitty_scrollback_nvim⋅kitten⋅/home/michael/.config/nvim/lazyPlugins/pack/lazyPlugins/start/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py↴
# ↴
#⋅Browse⋅scrollback⋅buffer⋅in⋅nvim↴
# map⋅kitty_mod+h⋅kitty_scrollback_nvim↴
#⋅Browse⋅output⋅of⋅the⋅last⋅shell⋅command⋅in⋅nvim↴
# map⋅kitty_mod+g⋅kitty_scrollback_nvim⋅--config⋅ksb_builtin_last_cmd_output↴
#⋅Show⋅clicked⋅command⋅output⋅in⋅nvim↴
# mouse_map⋅ctrl+shift+right⋅press⋅ungrabbed⋅combine⋅:⋅mouse_select_command_output⋅:⋅kitty_scrollback_nvim⋅--config⋅ksb_builtin_last_visited_cmd_output↴
{
  pkgs,
  lib,
  ...
}: {
  imports = [];
  options = {};
  config = {
    # nixpkgs = {
    #   overlays =
    #     [ (final: prev: { inherit (pkgs.unstable) kitty-themes; }) ];
    # };
    programs = {
      kitty = let
        test_font = "FranSans-Tile";
        base_font = "JetBrainsMonoNFM";
        font = "${base_font}-Regular";
        bold_font = "${base_font}-Bold";
        italic_font = "${base_font}-Italic";
        BI_font = "${base_font}-BoldItalic";
      in {
        enable = true;
        package = pkgs.emptyDirectory;
        # NOTE: might contribute extra options to this, a module for theme that can specify the package as well
        theme = "Gruvbox Material Dark Hard";
        font = {
          # NOTE: This should be install globally as part of fontConfig
          # prefer this to FiraCode, the r's are more readable with the current size
          name = font;
          # name = test_font;
          size = 9;
        };
        shellIntegration.enableZshIntegration = true;
        settings = {
          # Disable kitty's built-in config hot-reload. Its watcher
          # (kitten __watch_conf__) follows the nix-store symlink of kitty.conf
          # and recursively watches /nix/store, accumulating ~64k inotify
          # watches and exhausting fs.inotify.max_user_watches for the user --
          # which starves every other inotify consumer (waybar battery,
          # dbus-broker cgroups, ...). Home Manager reloads kitty on switch
          # instead (see home.activation.reloadKitty below).
          auto_reload_config = -0.1;
          # Want a huge buffer. 100000 in-memory lines is the wrong way to get
          # it -- upstream: "very large scrollback ... can slow down performance
          # of the terminal and also use large amounts of RAM. Instead, consider
          # using scrollback_pager_history_size". So: a modest live buffer plus a
          # large on-disk history that the pager (kitty_scrollback_nvim, bound to
          # kitty_mod+f below) reads.
          scrollback_lines = 10000;
          scrollback_pager_history_size = 1024; # MB on disk
          enable_audio_bell = true;
          bold_font = bold_font;
          italic_font = italic_font;
          bold_italic_font = BI_font;
          strip_trailing_spaces = "smart";
          enabled_layouts = "Splits";
          window_border_width = "4.0pt";
          inactive_border_color = "#5c5c5c";
          draw_minimal_borders = "yes";
          # WARN: Did not like change, might modify later.
          # window_margin_width = "1";
          # TODO: (med prio) setup later
          # tab_bar_style = "custom";
          allow_remote_control = "socket-only";
          listen_on = "unix:/tmp/kitty";
          disable_ligatures = "always";
          # PERF: input_delay/repaint_delay/sync_to_monitor are back at their
          # upstream defaults. The old 0/2/no trio targeted ~500 FPS with the
          # vblank cap removed, and every one of those frames is a wl_surface
          # commit Hyprland has to composite -- with blur, because the global
          # `opacity-all` window_rule (features/hm/wayland/hyprland.nix) makes
          # every window translucent, so no opaque-region cull applies. Measured
          # ~3 points of extra Hyprland CPU under a 200 lines/sec workload, on a
          # box whose Renoir iGPU already sits at 60-68% busy.
          #
          # input_delay = 0 was also the direct cause of the "erratic" redraws:
          # upstream warns it "might cause flicker in full screen programs that
          # redraw the entire screen on each loop, because kitty is so fast that
          # partial screen updates will be drawn" -- i.e. nvim.
          #
          # Kept: IME off is a real input-latency win with no cost here.
          "wayland_enable_ime" = "no";
          # only works in macos
          # background_blur = 1;
          # background_opacity = 0.9;
          cursor_shape_unfocused = "beam";
          # Plain blink, no easing. The easing function turns a 2-state toggle
          # into a continuous fade -- upstream: "turning on animations uses extra
          # power as it means the screen is redrawn multiple times per blink
          # interval" -- which redraws the focused window every repaint_delay for
          # the 15s cursor_stop_blinking_after window following each keystroke.
          cursor_blink_interval = "0.5";
          # cursor_trail's value is a dwell threshold in MILLISECONDS: the trail
          # only follows a cursor that held its position longer than this, which
          # is upstream's guard against trails firing "during UI updates in
          # complex applications". 1ms defeated the guard, so nvim/shell redraws
          # animated a trail (0.1-0.4s decay each). 40ms keeps the effect for
          # deliberate jumps and drops it for redraw churn.
          cursor_trail = 40;
        };
        # TODO: (low prio) need to set more keybindings
        # ref: https://sw.kovidgoyal.net/kitty/layouts/#the-splits-layout
        # NOTE: for todo: the most important keybindings are already setup.
        keybindings = {
          # ctrl+shift+\
          "kitty_mod+0x5c" = "launch --location=vsplit";
          # ctrl+shift+-
          "ctrl+shift+minus" = "launch --location=hsplit";
          # ctrl+ "+"
          "ctrl+equal" = "change_font_size all +0.5";
          # ctrl+ "-"
          "ctrl+minus" = "change_font_size all -1.0";
          # map ctrl+shift+v paste_from_clipboard
          # map ctrl+shift+c copy_to_clipboard

          "kitty_mod+f" = "kitty_scrollback_nvim";
          "kitty_mod+g" = "kitty_scrollback_nvim --config ksb_builtin_last_cmd_output";
          # "kitty_mod+j"
          # "kitty_mod+j"
        };

        extraConfig = ''
          action_alias kitty_scrollback_nvim kitten ${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py
          mouse_map ctrl+shift+right press ungrabbed combine : mouse_select_command_output : kitty_scrollback_nvim --config ksb_builtin_last_visited_cmd_output
          # PERF: disable ligatures
          font_features ${font} -liga
          font_features ${bold_font} -liga
          font_features ${italic_font} -liga
        '';
      };
    };

    # auto_reload_config is off (see programs.kitty.settings); instead, poke any
    # running kitty to re-read kitty.conf after HM rewrites it. SIGUSR1 is
    # kitty's documented reload signal. A reload is cheap and idempotent, so we
    # fire on every switch rather than only when kitty.conf actually changed.
    home.activation.reloadKitty =
      lib.hm.dag.entryAfter ["linkGeneration"] ''
        run ${pkgs.procps}/bin/pkill -USR1 -x kitty || true
      '';
  };
}
