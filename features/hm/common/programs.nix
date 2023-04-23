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
<<<<<<< HEAD
       skim = {
              enable = true;
              enableZshIntegration = true;
            };
      # downloader
      aria.enable = true;
=======
      skim = {
        enable = true;
        enableZshIntegration = true;
      };
      # downloader
      aria2.enable = true;
>>>>>>> 72386ef (FIX: misspellings.)
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
<<<<<<< HEAD
      gutui.enable = true;
=======
      gitui.enable = true;
>>>>>>> 72386ef (FIX: misspellings.)
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
<<<<<<< HEAD
      kitty = {
        enable = true;
        package = pkgs.unstable.kitty;
        theme = "Gruvbox Material Dark Hard";
      };
=======
>>>>>>> 72386ef (FIX: misspellings.)
      foot = { enable = true; };
      # launcher
      rofi = {
        enable = true;
        theme = "gruvbox-dark-hard";
      };
      firefox = {
        enable = true;
<<<<<<< HEAD
        package = pkgs.firefox-devedition-bit;
=======
        package = pkgs.firefox-devedition-bin;
>>>>>>> 72386ef (FIX: misspellings.)
      };
    };
  };
}
