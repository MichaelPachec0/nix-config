{ pkgs, ... }: {
  imports = [ ];
  options = { };
  config = {
    nixpkgs = {
      overlays =
        [ (final: prev: { kitty-themes = pkgs.unstable.kitty-themes; }) ];
    };
    programs = {
      kitty = {
        enable = true;
        package = pkgs.unstable.kitty;
        theme = "Gruvbox Material Dark Hard";
        font = {
          name = "JetBrains Mono Regular Nerd Font Complete";
          package = pkgs.jetbrains-mono;
          size = 9;
        };
        settings = {
          scrollback_lines = 10000;
          enable_audio_bell = true;
          bold_font = "JetBrains Mono Bold Nerd Font Complete";
          italic_font = "JetBrains Mono SemiBold Italic Nerd Font Complete";
          bold_italic_font = "JetBrains Mono Bold Italic Nerd Font Complete";
          strip_trailing_spaces = "smart";
          enabled_layouts = "Splits";
          # TODO: setup later
          # tab_bar_style = "custom";
        };
        # need to set more keybindings
        # ref: https://sw.kovidgoyal.net/kitty/layouts/#the-splits-layout
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
        };
      };
    };
  };
}
