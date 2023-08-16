{
  config,
  lib,
  pkgs,
  ...
}: {
  config = {
    programs = lib.attrsets.recursiveUpdate (lib.attrsets.recursiveUpdate
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
        } (lib.attrsets.optionalAttrs config.audio.enable {
          ncmpcpp.enable = true;
        })) (lib.attrsets.optionalAttrs config.graphical.enable {
        # terminal that uses gpu for fast rendering
        foot = {enable = true;};
        # launcher
        rofi = {
          enable = true;
          package = pkgs.unstable.rofi-wayland;
          theme = "gruvbox-dark-hard";
          plugins = with pkgs; [
            # network manager for dmenu
            networkmanager_dmenu
            # clipboard
            clipmenu
            # keepass
            unstable.keepmenu
            # vpn
            rofi-vpn
            # top
            rofi-top
            # calc
            rofi-calc
            # emoji TODO: decide between emojipick or this
            rofi-emoji
            # systemd
            rofi-systemd
            # menus?
            rofi-menugen
            # bt
            rofi-bluetooth
            # power
            rofi-power-menu
            # audio routing
            rofi-pulse-select
            # rofi file-browser
            rofi-file-browser
            # pinentry
            pinentry-rofi
            tor-browser-bundle-bin
          ];
          terminal = "${lib.getExe pkgs.unstable.kitty}";
          location = "center";
        };
        firefox = {
          enable = true;
          package = pkgs.firefox-devedition-bin.overrideAttrs (let
            # NOTE: This is for 116.0b8.
            # TODO: (high prio) this is old now, either move to use another src (like
            # mozilla's flake) or keep overriding it here.
            url = "https://archive.mozilla.org/pub/devedition/releases/116.0b8/linux-x86_64/en-US/firefox-116.0b8.tar.bz2";
            sha256 = "fdde9c378b5b184e8ed81d62eb03dd39bae52496e742ed960fd16eeb299c6662";
          in
            old: {
              src = builtins.fetchurl {inherit url sha256;};
            });
        };
      })) (lib.attrsets.optionalAttrs config.devMachine.enable {
      direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
      gh = {
        enable = true;
        extensions = [pkgs.gh-eco pkgs.gh-dash];
        settings = {
          editor = "vim";
          git_protocol = "ssh";
        };
      };
      vscode = {
        enable = true;
        enableExtensionUpdateCheck = false;
        enableUpdateCheck = false;
        mutableExtensionsDir = true;
        userSettings = {
          "nix.serverPath" = "nil";
          "nix.enableLanguageServer" = true;
          "nix.formatterPath" = "alenjandra";
          "[nix]"."editor.defaultFormatter" = "jnoortheen.nix-ide";
        };
        # NOTE: This is from nixpkgs (stable)
        extensions = with pkgs.stable.vscode-extensions;
          [
          ]
          # NOTE: This is from nixpkgs (unstable)
          ++ (with pkgs.vscode-extensions; [
            vadimcn.vscode-lldb
            jnoortheen.nix-ide
            kamadorueda.alejandra
          ])
      };
      git = {
        enable = true;
        package = pkgs.gitFull;
        userName = "Michael Pacheco";
        userEmail = "git@michaelpacheco.org";
        ignores = ["*~" "*.swap" ".vscode" ".idea"];
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
    });
  };
}
