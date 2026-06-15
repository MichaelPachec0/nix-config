{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    # jerry.homeManagerModules.default
  ];
  options = {};
  config = let
    # rofi-unwrapped = let
    #   # rev ="0abd887";
    #   # rev = "5df2d3a13725a3c7ee3fdb9d2dcd6bdca19115fd";
    #   # version = "2025-01-11-${rev}+wayland";
    #   # hash = "sha256-AQl5WIfNdn8D6o1MO1Hv9JQGzFYLu5skDyIsu7qFiW4=";
    # in
    #   pkgs.master.rofi-wayland-unwrapped.overrideAttrs (old: {
    #     # inherit version;
    #     # src = pkgs.fetchFromGitHub {
    #     #   inherit (old.src) owner repo;
    #     #   inherit hash rev;
    #     #   fetchSubmodules = true;
    #     # };
    #     patches =
    #       (old.patches or [])
    #       ++ [
    #         (pkgs.fetchpatch {
    #           url = "https://patch-diff.githubusercontent.com/raw/lbonn/rofi/pull/143.patch";
    #           # hash = lib.fakeHash;
    #           hash = "sha256-c/1ULzrf6WoXzsdPbwYM5lerU5g251UGUndGy4CEfB0=";
    #         })
    #       ];
    #     nativeBuildInputs = (old.nativeBuildInputs or []) ++ (with pkgs.xorg; [xcbutilkeysyms]);
    #     buildInputs = (old.buildInputs or []) ++ (with pkgs.xorg; [xcbutilkeysyms]);
    #   });
    # package = pkgs.rofi-wayland.override {inherit rofi-unwrapped;};
    rofi-bt =
      pkgs.rofi-bluetooth.overrideAttrs
      # WARN: --status complains about bc not found, add it.
      # TODO: check if this is fixed.
      (_old: {
        installPhase = ''
          runHook preInstall

          install -D --target-directory=$out/bin/ ./rofi-bluetooth

          # this is the issue
          wrapProgram $out/bin/rofi-bluetooth \
            --prefix PATH ":" ${lib.makeBinPath [pkgs.bluez pkgs.bc]}

          runHook postInstall
        '';
      });
    # mkRofiPlugin = plugin: rofi-unwrapped: plugin.override {inherit rofi-unwrapped;};

    # rofi-vpn = mkRofiPlugin pkgs.rofi-vpn rofi-unwrapped;

    script = lib.getExe pkgs.rofi-power-menu;
    fullscript = pkgs.writeShellScriptBin "power.sh" ''
      ${lib.getExe config.programs.rofi.package} \
        -show p \
        -modi p:'${script} --symbols-font "Symbols Nerd Font Mono"' \
        -font "JetBrains Mono NF 16" \
        -theme gruvbox-dark \
        -theme-str 'window {width: 8em;} listview {lines: 6;}'
    '';
  in {
    programs.rofi = {
      # inherit package;
      enable = true;
      theme = "gruvbox-dark-hard";
      extraConfig = {
        modi = "calc,emoji,ssh,combi,run,top,filebrowser";
        show-icons = true;
        sidebar-mode = true;
        config-modi = "window,drun";
      };
      plugins = with pkgs;
        [
          # network manager for dmenu
          networkmanager_dmenu
          # clipboard
          clipmenu
          # keepass
          keepmenu
          # vpn
          # rofi-vpn
          rofi-vpn

          # top
          # (mkRofiPlugin pkgs.rofi-top rofi-unwrapped)

          rofi-top
          # (mkRofiPlugin pkgs.rofi-top rofi-unwrapped)
          rofi-calc
          # (mkRofiPlugin pkgs.rofi-calc rofi-unwrapped)
          # emoji TODO: (med prio) decide between emojipick or this
          # (mkRofiPlugin pkgs.rofi-emoji rofi-unwrapped)
          # rofi-emoji-wayland
          rofi-emoji
          # systemd
          rofi-systemd
          # menus?
          rofi-menugen
          # power
          # rofi-power-menu
          # audio routing
          rofi-pulse-select
          # rofi file-browser
          # (mkRofiPlugin rofi-file-browser rofi-unwrapped)
          # pinentry
          pinentry-rofi
        # 2025-11-05: tor-browser-bundle-bin to tor-browser
          tor-browser
        ]
        ++ [
          # bt
        ];
      # terminal = "${lib.getExe pkgs.kitty}";
      # WARN: the above for some reason recompiles kitty? WTF
      terminal = "kitty";
      location = "center";
    };
    # programs.jerry = let
    #   # _jerry = mkRofiUPlugin jerry.packages.${pkgs.system}.default rofi-unwrapped;
    #   # package = _jerry.override {
    #   #   mpv = config.programs.mpv.package;
    #   #   imagePreviewSupport = true;
    #   #   infoSupport = true;
    #   #   withRofi = true;
    #   # };
    #   # package = jerry.packages.${pkgs.system}.default.override {
    #   #   mpv = config.programs.mpv.package;
    #   #   imagePreviewSupport = true;
    #   #   infoSupport = true;
    #   #   withRofi = true;
    #   # };
    # in {
    #   # inherit package;
    #   enable = true;
    #   config = {
    #     player = "mpv";
    #     chafa_method = "kitty";
    #     manga_opener = "feh";
    #     manga_format = "image";
    #     image_preview = true;
    #     sub_or_dub = "sub";
    #     score_on_completion = false;
    #     ueberzug_output = "kitty";
    #     provider = "gogoanime";
    #   };
    # };
    xdg.desktopEntries = {
      # rofi-vpn = {
      #   name = "VPN";
      #   exec = "${rofi-vpn}/bin/rofi-vpn";
      #   terminal = false;
      # };
      rofi-bt = {
        name = "BT: Bluetooth";
        exec = "${lib.getExe rofi-bt}";
        terminal = false;
      };
      # jerry-rofi = {
      #   name = "jerry";
      #   exec = "${lib.getExe config.programs.jerry.package} --dmenu";
      #   terminal = false;
      # };
      # rofi \
      #   -show p \
      #   -modi p:'rofi-power-menu --symbols-font "Symbols Nerd Font Mono"' \
      #   -font "JetBrains Mono NF 16" \
      #   -theme gruvbox-dark \
      #   -theme-str 'window {width: 8em;} listview {lines: 6;}'
      power-rofi = {
        name = "power-menu";
        exec = "${lib.getExe fullscript}";
        terminal = false;
      };
    };
    home.packages = with pkgs; [
      #   rofi-bt
      # rofi-power-menu
      # fullscript
      # failed with gcc 14 errors, might push fix?
      # spaceFM
    ];

    # networkmanager_dmenu
    # # clipboard
    # clipmenu
    # # keepass
    # keepmenu
    # # emojis
    # emojipick
    # # vpn
    # rofi-wayland
    # rofi-vpn
    # # top
    # rofi-top
    # # calc
    # rofi-calc
    # # emoji TODO: (med prio) decide between emojipick or this
    # rofi-emoji
    # # systemd
    # rofi-systemd
    # # menus?
    # rofi-menugen
    # # bt
    # rofi-bluetooth
    # # power
    # rofi-power-menu
    # # audio routing
    # rofi-pulse-select
    # # rofi file-browser
    # rofi-file-browser
    # # pinentry
    # pinentry-rofi

    # TODO: this need sops to be useful, also this does not have support for challenge-response
    # xdg.configFile = {
    #   "keepmenu/config.ini".text = lib.generators.toINI {} {
    #     demu.demu_command = "${lib.getExe cfg.programs.rofi.package} -dmenu -i";
    #     dmenu_passphrase.obscure = true;
    #
    #   };
    # };
  };
}
