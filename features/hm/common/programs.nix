{ config, lib, pkgs, ... }: {
  config = {
    programs = (lib.attrsets.recursiveUpdate (lib.attrsets.recursiveUpdate
      (lib.attrsets.recursiveUpdate {
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
        aria2.enable = true;
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
        gitui.enable = true;
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

      } (lib.attrsets.optionalAttrs (config.audio.enable) {
        ncmpcpp.enable = true;

      })) (lib.attrsets.optionalAttrs (config.graphical.enable) {
        # terminal that uses gpu for fast rendering
        foot = { enable = true; };
        # launcher
        rofi = {
          enable = true;
          theme = "gruvbox-dark-hard";
        };
        firefox = {
          enable = true;
          package = pkgs.firefox-devedition-bin;
        };

      })) (lib.attrsets.optionalAttrs (config.devMachine.enable) {
        gh = {
          enable = true;
          extensions = [ pkgs.gh-eco pkgs.gh-dash ];
          settings = {
            editor = "vim";
            git_protocol = "ssh";

          };
        };
        git = {
          enable = true;
          package = pkgs.gitFull;
          userName = "Michael Pacheco";
          userEmail = "git@michaelpacheco.org";
          ignores = [ "*~" "*.swap" ".vscode" ".idea" ];
          diff-so-fancy = {
            enable = true;
            markEmptyLines = true;
            useUnicodeRuler = true;
          };
          signing = {
            signByDefault = true;
            key = "2A1E939CF48AC3CC";
          };
        };
      }));
  };
}
