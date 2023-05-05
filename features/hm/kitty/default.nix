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
          enable_audio_bell = false; 
          bold_font = "JetBrains Mono Bold Nerd Font Complete";
          italic_font = "JetBrains Mono SemiBold Italic Nerd Font Complete";
          bold_italic_font = "JetBrains Mono Bold Italic Nerd Font Complete";
          #font_features = "JetBrainsMonoNerdFontComplete-Regular +calt +ss02 +cv01";
          strip_trailing_spaces = "smart";
          enabled_layouts = "Splits, all";
          #tab_bar_style = "powerline";
          #tab_powerline_style = "round";

        };
      };
    };
  };
}
