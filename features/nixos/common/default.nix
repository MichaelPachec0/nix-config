{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  # imports = [../../../overlays/modules/usbmuxd];
  options = {
    audio.enable = lib.mkEnableOption "Installs common audio apps.";
    devMachine.enable = lib.mkEnableOption "Install common developer apps.";
    report-changes.enable = lib.mkEnableOption "Create a report after successful nixOS generation creation";
    machine.vm.enable = lib.mkEnableOption "Not a real machine";
  };
  config = {
    programs.neovim = {
      package = inputs.neovim.packages.${pkgs.stdenv.hostPlatform.system}.default;
      enable = true;
      defaultEditor = true;
      vimAlias = true;
      viAlias = true;
    };
    documentation = {
      enable = true;
      dev.enable = true;
    };

    services.logrotate = {
      enable = true;
    };

    programs.zsh.enable = true;
    nixpkgs.overlays = [
      # 2025-1-10 removed these as these are old
      (_final: _prev: {
        # libplist = prev.libplist.overrideAttrs (old: rec {
        #   version = "2.6.1";
        #   src = prev.fetchFromGitHub {
        #     owner = old.src.owner;
        #     repo = old.pname;
        #     rev = "e8791e2d8b1d1672439b78d31271a8cf74d6a16d";
        #     hash = "sha256-sKLFfv+B5UuYjMxG8a6GbP6BvohkhkqjS5+RBncHvxI=";
        #   };
        #   preAutoreconf = ''
        #     export RELEASE_VERSION=${version}
        #   '';
        # });
        # libimobiledevice-glue = (prev.libimobiledevice-glue.override {inherit (final) libplist;}).overrideAttrs (old: {
        #   # NOTE: this differiates from nixpkgs version.
        #   version = "0.0.0-master";
        #   src = prev.fetchFromGitHub {
        #     owner = old.src.owner;
        #     repo = old.pname;
        #     rev = "14c2e4b64b2bd6189d06d858bf4898d3a9f5a6e4";
        #     hash = "sha256-QNwyvPAY46a/jtpyPhKyuBc9ATWtgwmRDgjtlpZ3BTo=";
        #   };
        # });
        # libusbmuxd = prev.libusbmuxd.override {inherit (final) libplist;};
        # libimobiledevice = (prev.libimobiledevice.override {inherit (final) libplist libimobiledevice-glue libusbmuxd;}).overrideAttrs (old: {
        #   # NOTE: this differiates from nixpkgs version.
        #   version = "0.0.0-master";
        #   src = prev.fetchFromGitHub {
        #     owner = old.src.owner;
        #     repo = old.pname;
        #     rev = "9ccc52222c287b35e41625cc282fb882544676c6";
        #     hash = "sha256-pNvtDGUlifp10V59Kah4q87TvLrcptrCJURHo+Y+hs4=";
        #   };
        #   # NOTE: patches to compile with recent clang are not needed anymore.
        #   patches = [];
        # });
        # libtatsu = prev.callPackage ({
        #   lib,
        #   stdenv,
        #   fetchFromGitHub,
        #   autoreconfHook,
        #   pkg-config,
        #   curl,
        #   libplist,
        # }:
        #   stdenv.mkDerivation rec {
        #     pname = "libtatsu";
        #     version = "1.0.0";
        #
        #     src = fetchFromGitHub {
        #       owner = "libimobiledevice";
        #       repo = pname;
        #       rev = "6fd8a51bbdb4411915663f9686d4a2045f61997c";
        #       hash = "sha256-6mg/sVh4tHOLatEhwc2pvqpxrObZPnHdLBORWMLc7bA=";
        #     };
        #     outputs = ["out" "dev"];
        #     nativeBuildInputs = [
        #       autoreconfHook
        #       pkg-config
        #     ];
        #     buildInputs = [
        #       curl
        #       libplist
        #     ];
        #     preAutoreconf = ''
        #       export RELEASE_VERSION=${version}
        #     '';
        #     meta = {
        #       description = "Library handling the communication with Apple's Tatsu Signing Server (TSS)";
        #       homepage = "https://github.com/libimobiledevice/libtatsu";
        #       license = lib.licenses.lgpl21Plus;
        #       # maintainers = with lib.maintainers; [  ];
        #     };
        #   }) {};
        # idevicerestore =
        #   prev
        #   .idevicerestore
        #   .overrideAttrs (old: {
        #     version = "1.0.0+date=2024-06-04";
        #     src = prev.fetchFromGitHub {
        #       owner = old.src.owner;
        #       repo = old.pname;
        #       rev = "df06f4d859f7bb0896d1b15ade5b9d2b58626a0e";
        #       hash = "sha256-CzUOrumygTa3lPTD9vZutVEyloCVVnJ0BA0vH7KOvd4=";
        #     };
        #     buildInputs = old.buildInputs ++ [final.libtatsu];
        #     patches = (old.patches or []) ++ [../../../helpers/idevicerestore.patch];
        #   });
        # buildInputs = [t final.libimobiledevice final.libusbmuxd final.libirecovery];
        # nativeBuildInputs = old.nativeBuildInputs ++ [libplist];
      })
    ];

    # NOTE: faster dbus implementation than default daemon
    # services.dbus.implementation = "broker";

    # Enable tor
    services.tor = {
      enable = true;
      client = {
        enable = true;
        socksListenAddress = {
          addr = "127.0.0.1";
          port = 9050;
          IsolateDestAddr = true;
        };
        dns.enable = true;
      };
      settings = {ClientUseIPv4 = true;};
    };

    services.privoxy = {
      enable = true;
      enableTor = true;
    };

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";

    environment.systemPackages = with pkgs;
      [
        nix-your-shell
        # brings gix a faster git client
        gitoxide
        gitFull
        curl
        wget
        # find alternative
        fd
        # better grep
        ripgrep
        # terminal file manager
        # WARN: disabled for kore since rustc has not been updated for 1.74
        # joshuto
        # images in the terminal
        # viu
        # neofetch
        # thefuck
        pay-respects
        # powertop
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
        cabextract
        p7zip
        rpm

        # nix generation diff tool
        nvd
        # process mon
        btop
        home-manager

        # iOS
        # libimobiledevice
        # ifuse
        # idevicerestore

        # Hex stuff
        ## hex editor
        ### TODO: Decide on one
        # TODO: remove for now, decide to fix later
        # (hexcurse.overrideAttrs (old: {
        #   src = pkgs.fetchFromGitHub {
        #     owner = "prso";
        #     repo = "hexcurse-ng";
        #     rev = "1c15a63d6b0e7c03bba96d83a72bf0c64f6be296";
        #     hash = "sha256-PIVApm1ZkW9ApptNasQGGi2o6OifI8DNfnca3Ew9Eks=";
        #   };
        #   # remove obsolete patches
        #   patches = [];
        # }))
        ### hex viewer with diff
        # dhex
        ### don't know about this one. in go with hex on top of ascii
        hecate
        ## hex viewer
        ### rust hex viewer
        hexyl
        ### also rust but with vim keybinds
        # xxv
        ## cool hex things
        ### hex visualizer
        pixd
        shellcheck
        # hacks around color removal when piping
        expect
        # space age sed, fancy sed: https://github.com/ms-jpq/sad
        sad

        jq
        # man-pages
        # man-pages-posix
      ]
      ++ lib.optionals config.audio.enable [pavucontrol ncpamixer playerctl]
      ++ lib.optionals (!config.machine.vm.enable) [
        # graphical/terminal browser
        # links2
        pciutils
        usbutils
      ]
      ++ lib.optionals config.devMachine.enable [
        powertop-git
        nixpkgs-review
        crate2nix
        nix-prefetch
        nix-prefetch-git
        nix-prefetch-github
        nix-index
        nixfmt
        # WARN: switch to flake based dev, do not need a global rust-analyzer or clippy
        # rust-analyzer
        # clippy
        # csv files in terminal
        tidy-viewer
        android-tools
        # 2025-11-05: wakatime to wakatime-cli
        wakatime-cli
      ]
      ++ lib.optionals config.services.hardware.bolt.enable [bolt];
    # TODO: move to using nixos module. Might be a bit difficult since the nixos stable does not have this merged, but unstable does.
    services.usbmuxd = {
      enable = true;
      package = pkgs.usbmuxd;
    };
    services.udev.packages = with pkgs;
      lib.optionals config.devMachine.enable [
        # 2025-11-11: android-udev-rules is now standard, the package is now EOL
        # android-udev-rules
        polar
      ];

    # systemd.= ''
    #   DefaultTimeoutStopSec=10s
    # '';
    # NOTE: newer unstable does this.
    systemd.settings.Manager = {
      DefaultTimeoutStopSec = "10s";
    };
    # NOTE: gives a really nice diff between generations
    # src: https://github.com/luishfonseca/dotfiles/blob/32c10e775d9ec7cc55e44592a060c1c9aadf113e/modules/upgrade-diff.nix
    system.activationScripts.diff = {
      supportsDryActivation = true;
      # ${lib.getExe pkgs.nvd} --nix-bin-dir=${pkgs.nix}/bin diff /run/current-system "$systemConfig"
      text = ''
        if [[ -e /run/current-system ]]; then
          echo "#############################        diff to current-system        ##############################"
          echo "#                                                                                               #"
          ${pkgs.nvd}/bin/nvd --nix-bin-dir=${config.nix.package}/bin diff $(${pkgs.coreutils}/bin/readlink "/run/current-system") "$systemConfig" | tee /etc/gradientos-changelog
          echo "#                                                                                               #"
          echo "#############################      end diff to current-system      ##############################"
        fi
      '';
    };
  };
  # // (lib.optionalAttrs report-changes {
  # });
}
