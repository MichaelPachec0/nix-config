{ config, lib, pkgs, ... }: {
  config = {
    programs = {
      # cat alternative
      bat.enable = true;
      # tldr alternative
      tealdeer = {
        enable = true;
        settings = {
          display.use_pager = true;
          updates.auto_update = true;
        };
      };
      # cmd fuzzy finder, for now default to using fzf
       skim = {
              enable = true;
              enableZshIntegration = true;
            };
      # downloader
      aria.enable = true;
      # cheat sheet commands
      navi = {
        enable = true;
        enableZshIntegration = true;
      };
      # terminal document converter
      pandoc.enable = true;
      # smarter cd ( with caveats)
      zoxide.enable = true;
      # terminal git ui (uses ncurses iirc)
      gutui.enable = true;
      # modern ls alterantive
      exa = {
        enable = true;
        icons = true;
        git = true;
        enableAliases = true;
        extraOptions = [
          "--group-directories-first"
          "--header"
          "--group"
          "--time-style=long-iso"
          "--extended"
        ];
      };

    } // lib.attrsets.optionalAttrs (config.audio.enable) {
      ncmpcpp.enable = true;

    } // lib.attrsets.optionalAttrs (config.graphical.enable) {
      # terminal that uses gpu for fast rendering
      kitty = {
        enable = true;
        package = pkgs.unstable.kitty;
        theme = "Gruvbox Material Dark Hard";
      };
      foot = { enable = true; };
      # launcher
      rofi = {
        enable = true;
        theme = "gruvbox-dark-hard";
      };
      firefox = {
        enable = true;
        package = pkgs.firefox-devedition-bit;
      };
    };
  };
}
