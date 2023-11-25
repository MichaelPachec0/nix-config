#⋅kitty-scrollback.nvim⋅Kitten⋅alias↴

# action_alias⋅kitty_scrollback_nvim⋅kitten⋅/home/michael/.config/nvim/lazyPlugins/pack/lazyPlugins/start/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py↴
# ↴
#⋅Browse⋅scrollback⋅buffer⋅in⋅nvim↴
# map⋅kitty_mod+h⋅kitty_scrollback_nvim↴
#⋅Browse⋅output⋅of⋅the⋅last⋅shell⋅command⋅in⋅nvim↴
# map⋅kitty_mod+g⋅kitty_scrollback_nvim⋅--config⋅ksb_builtin_last_cmd_output↴
#⋅Show⋅clicked⋅command⋅output⋅in⋅nvim↴
# mouse_map⋅ctrl+shift+right⋅press⋅ungrabbed⋅combine⋅:⋅mouse_select_command_output⋅:⋅kitty_scrollback_nvim⋅--config⋅ksb_builtin_last_visited_cmd_output↴
{pkgs, ...}: {
  imports = [];
  options = {};
  config = {
    nixpkgs = {
      overlays =
        [ (final: prev: { kitty-themes = pkgs.unstable.kitty-themes; }) ];
    };
    programs = {
      kitty = {
        enable = true;
        package = pkgs.unstable.kitty;
        # NOTE: might contribute extra options to this, a module for theme that can specify the package as well
        theme = "Gruvbox Material Dark Hard";
        font = {
          # NOTE: This should be install globally as part of fontConfig
          # prefer this to FiraCode, the r's are more reable with the current size
          name = "JetBrainsMono NF Regular";
          size = 9;
        };
        shellIntegration.enableZshIntegration = true;
        settings = {
          # NOTE: want a *huge* buffer, dont really care about the memory usuage,
          #   should have enough.
          scrollback_lines = 100000;
          enable_audio_bell = true;
          bold_font = "JetBrainsMono NF Bold";
          italic_font = "JetBrainsMono NF Italic";
          bold_italic_font = "JetBrainsMono NF Bold Italic";
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
          "ctrl+equal" = "change_font_size all +2.0";
          # ctrl+ "-"
          "ctrl+minus" = "change_font_size all -2.0";
          # map ctrl+shift+v paste_from_clipboard
          # map ctrl+shift+c copy_to_clipboard
          "kitty_mod+h" = "kitty_scrollback_nvim";
          "kitty_mod+g" = "kitty_scrollback_nvim⋅--config⋅ksb_builtin_last_cmd_output";
        };
        extraConfig = ''
          action_alias kitty_scrollback_nvim kitten ${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty-scrollback-nvim.py
          mouse_map⋅ctrl+shift+right⋅press⋅ungrabbed⋅combine⋅:⋅mouse_select_command_output⋅:⋅kitty_scrollback_nvim⋅--config⋅ksb_builtin_last_visited_cmd_output↴

        '';
      };
    };
  };
}
