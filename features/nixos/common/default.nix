{ config, pkgs, lib, ... }: {
  imports = [ ];
  options = {
    audio.enable = lib.mkEnableOption "Installs common audio apps.";
    devMachine.enable = lib.mkEnableOption "Install common developer apps.";
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
        powertop
        pciutils
        usbutils
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
        btop
        unstable.home-manager
      ]
      ++ lib.optionals (config.audio.enable) [ pavucontrol ncpamixer playerctl ]
      ++ lib.optionals (config.devMachine.enable) [
        nix-prefetch
        nix-prefetch-git
        nix-prefetch-github
        nix-index
        nixfmt
        # csv files in terminal
        tidy-viewer
      ];
  };
}

