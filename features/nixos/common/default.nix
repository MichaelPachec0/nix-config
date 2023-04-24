{ config, pkgs, lib, ... }: {
  imports = [ ];
  options = {
    audio.enable = lib.mkEnableOption "Installs common audio apps.";
    graphical.enable = lib.mkEnableOption "Install common graphical apps.";
  };
  config = {
    environment.systemPackages = with pkgs;
      [
        curl
        wget
        # graphical/terminal browser
        links2
        # find alternative
        fd
        # better grep
        ripgrep
        # terminal file manager
        joshuto
        # images in the terminal
        viu
        neofetch
        thefuck
        nixfmt
        powertop
        pciutils
        # extract 
        unzip
        zip
        p7zip
        pigz
        pbzip2
        pixz
        lzip
        lrzip
        lz4
        unrar-wrapper
        rpm

        neovim
        nvd

      ]
      ++ lib.optionals (config.audio.enable) [ pavucontrol ncpamixer playerctl ]
      ++ lib.optionals (config.graphical.enable) [
        nmap # network visualizer
        keepassxc # pass
        # telegram
        tdesktop
        kotatogram-desktop
        # discord
        unstable.webcord
        # vnc
        unstable.wayvnc
        remmina
        unstable.kanshi
        nyxt
      ];
  };
}
# mako notifications
# nmap
# mplayer
# tidy-viewer # csv printer terminal
# pavucontrol # audio
# ncpamixer # audio
# keepassxc # graphical
# tg # terminal but only for michael user
# tdesktop # graphical
# kotatogram-desktop
# playerctl # audio
# waybar-hyprland
# unstable-webcord
# slackterm
# themechanger
# brightnessctl #
# unstable.wayvnc # vnc
# remmina # vnc
# unstable.nil # nvim nix lsp michael user
# gsettings-qt
#     inputs.nwg-displays-pkgs.packages.${pkgs.system}.nwg-displays
# unstable.kanshi # screen control
# nyxt # vim/emacs browser

