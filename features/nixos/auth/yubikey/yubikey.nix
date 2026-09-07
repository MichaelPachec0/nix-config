{
  config,
  pkgs,
  lib,
  ...
}: let
  # NOTE:pamu2fcfg -opam://pamauth -ipam://pamauth
  # command to add yb for 2nd factor
  # keys [in order] =  799, 718, 838, 828, 766, 791, 082
  # This is fine to keep in plaintext since the private bits are on the yubikey themselves.
  # u2f_keys = "michael:wgLH6pLDQwlL/RbQnT/CtMuSFn7VH14qQLqkex1t9VsZRCcUMqaaiyqEjsmdAOxuXp9QBKZIXFLAhs/9McmZJQ==,+1u7ifuqoxjSIlCrY7vzF5uI1uhWiNGE39kv0tjjk+PoozygIQHi2CIB4hUDv9WXTPcJk4MhGiFSwGgwSecmhA==,es256,+presence:afjG830wh8QnGsZmb8raLQ5CP3RvXVyKhZBK1e8p8JHvcZHjrIkE8xQifHkjmKqTFL58EUGtePhotzfo9pjOaw==,9hyR6kqSYa3B1nNzpDywlzLVlKXFsEGNbx212VhS34IijOsQTX0o8NQkk+5Q/amQR/hS1UsRcTMx2Q/sxWgGfg==,es256,+presence:6JSCUKfEYEfv7lh4SUTfcrbaxmjD6DnlBMyD25z8MVuO1f9fQaKiaPKTxOtD8u2gUibi4tRUcj8BuUFiwumGhA==,UD90YpoXfGvHcjYBieOWcBmTp5IGoYbpsIAmcjE5chGFDAskKjCXLpxYilwKl7R/ZL9z9uUUqUuFmtdESB4eag==,es256,+presence:R5TGyqiAs9GfCUpBToAIjFRZiLNnc9ICfu95X+27T/DpqS8d4xOZiQnZrvmpC7cKdXnzDyouZOahtkJF2QQGrQ==,lcav0kKf72rJ7Ko7Yxn/hncMf8Vh/OBVTydtLnkiS4WpWDJXuWdmazSF1iiPwZ5Sf7c0gwUm0c52pnXSpL7uFA==,es256,+presence:Q0I4TGH8oTp9/KQcpepuQEv2YpmPwagUHsDfmSb6Y+tl5Q4Uu7J2DnHLh0yc2sGTrjthijdksW+bwF/WPXvpUg==,KQi+kBqBLu073JpQsxSXZbHn+nJBY8pQL/ZBT8KcGvdrwuYgF8rzNjMmfF3Rc+7B+/MzP91yldaW1Q7hC2PA7g==,es256,+presence:TbW3UH6hr8Q94zaiNh5zVJ97otKm1PfvwkvvpLf2u/8+6ENoo4eHx4lVaD3w/pnZjlNKNdA/c4fQniAe9qI9bA==,7Vo1bCaBliJB1XCWDtyii/GfW2IOS4JFYJ1iTIku9BtT5gboh3ZZDOLj+vPmEwUXjt91/zd4KmaHw8ktsQUKAA==,es256,+presence:wSXzaXYKntS3z5S1uxOigp5ipUPx2449us9wtUgbxGquUQ6NP55LOxcL0cI2LLPT6w7abkp57Vay0YeZ7eJ85Q==,wpbua+5NhHHkbdLXU6EajdMMdxrBcBchJQP5jTlghEKUvg71uCNhWnGNlwpCax9Q8Klve/zqx0/Es9GfAU7vSw==,es256,+presence";
  u2f_keys = "michael:FIH47PlEwW5mfA1CACTuPnIUGGFCnSZlBTul4KlMzRDl7x8hme4tZ5sH4gVdvHtzffaVeieqP2rkm7bf8TDMVQ==,YngIzzoVGwRHfoz/p2ZSdJwT/gFPOMq48PwswN5lX/+gvDVWC2NdHQfAe3tjri47sJ+Uq0wi+/lRfZZ29grF/Q==,es256,+presence:L45Cphx++6+mCemwWr/wRFYn5zddetqMnex3vjNe7yp5p2ZCpVzoHf/MAyINOG9kqgSa7tuVqYHzo3oLFTMRSw==,eoPBfTwzR41DS7iblrO4Mx+TfFBn7Yl9cYx3m7Wu2UBuDynJEfDSyqIk83bxaudiPSzIAwGkuqbc5qTCLHB4xQ==,es256,+presence";
  cfg = config.desktop;
  u2f_file = pkgs.writeText "u2f_mapping" u2f_keys;
  graphical = cfg.wayland.laptop || cfg.wayland.desktop;
  greetdEnabled = config.services.greetd.enable;

  # TODO: redo all scripts using writeShellApplication
  clearYubikey = pkgs.writeShellScriptBin "clear-yubikey" ''
    #!${pkgs.stdenv.shell}
    export PATH=${
      pkgs.lib.makeBinPath (with pkgs; [coreutils gnupg gawk gnugrep])
    };
    keygrips=$(
      gpg-connect-agent 'keyinfo --list' /bye 2>/dev/null \
        | grep -v OK \
        | awk '{if ($4 == "T") { print $3 ".key" }}')
    for f in $keygrips; do
      rm -v ~/.gnupg/private-keys-v1.d/$f
    done
    gpg --card-status 2>/dev/null 1>/dev/null || true
  '';

  clearYubikeyUser = user:
    pkgs.writeScript "clear-yubikey-user-${user}" ''
      #!${pkgs.stdenv.shell}
      ${pkgs.sudo}/bin/sudo -u ${user} ${clearYubikey}
    '';

  importYubikey = pkgs.writeShellScriptBin "import-yubikey" ''
    set -euo pipefail
    export PATH=${
      pkgs.lib.makeBinPath (with pkgs; [coreutils gnupg gawk gnugrep])
    };

    if [ "$#" -ne 1 ]; then
      echo "usage: import-yubikey key-id"
      exit 1
    fi

    export KEYID="$1"
    echo "Importing GPG public key '$KEYID'..."
    echo "gpg --recv $KEYID"
    gpg --recv "$KEYID"

    echo ""
    echo "Promping to trust GPG public key '$KEYID'..."
    echo "gpg --edit-key $KEYID trust"
    gpg --edit-key "$KEYID" trust

    echo "Finished importing '$KEYID'."
    exit 0
  '';
in {
  imports = [../pam/pam-u2f.nix];
  config = lib.mkIf config.yubikey.enable {
    hardware.gpgSmartcards.enable = true;
    programs = {
      gnupg.agent = {
        enable = true;
        # use gnupg's ssh support agent instead.
        enableSSHSupport = true;
        enableExtraSocket = true;
        enableBrowserSocket = true;
        # One package, both frontends. nixpkgs builds pinentry-gnome3 with
        # the gnome3, curses and tty flavors in a single derivation, so the
        # graphical build already carries bin/pinentry-curses and
        # bin/pinentry-tty next to the GTK3/GCR bin/pinentry-gnome3 that
        # bin/pinentry points at; that binary falls back to curses when no
        # display is reachable (ssh, VT). Adding pinentry-curses as a second
        # package would only duplicate bin/pinentry-curses. Headless hosts
        # get the curses-only build. The gnupg module wires gcr onto D-Bus
        # by itself when the package carries the gnome3 flavor.
        pinentryPackage =
          if graphical
          then pkgs.pinentry-gnome3
          else pkgs.pinentry-curses;
      };
    };
    services = {
      dbus.enable = true;
      # smartcard daemon
      pcscd.enable = true;
      # udev rules to access the yubikey
      udev.packages = [pkgs.yubikey-personalization];
    };

    # The gnupg module only installs gnupg itself; the pinentry package it
    # points gpg-agent at is not on PATH unless added here. This puts
    # pinentry, pinentry-curses and pinentry-tty (and pinentry-gnome3 on
    # graphical hosts) on PATH for anything besides gpg-agent that prompts.
    environment.systemPackages = with pkgs;
      [
        config.programs.gnupg.agent.pinentryPackage
        yubico-piv-tool
        #yubikey-manager
        # 2025-11-05: pcsctools changed to pcsc-tools
        pcsc-tools
        opensc
        importYubikey
        clearYubikey
      ]
      ++ lib.optionals graphical [
        # yubikey-personalization-gui
        yubioath-flutter
        # stable.yubikey-manager-qt
      ];
    security.pam = {
      u2f = {
        enable = true;
        settings = let
          # so that we have a common id, probably not needed since
          # $HOSTNAME is "" on nixos but might as well be explicit
          id = "pam://pamauth";
        in {
          authfile = "${u2f_file}";
          cue = true;
          origin = id;
          appid = id;
          debug = false;
        };
      };
      services = {
        sudo = {
          u2fAuth = true;
          use2Factor = false;
        };
        login = {
          u2fAuth = true;
          # u2f stays a `sufficient` alternative (control set below via rules),
          # not a forced 2nd factor, so keep this false.
          use2Factor = false;
          # Goal: password ALWAYS required, plus EITHER YubiKey or fingerprint.
          # NixOS' stock stack makes each factor a standalone `sufficient` that
          # sits before pam_unix, so a factor logs you in with no password.
          # Reorder: pam_unix first as `required` (no nullok), grab the token
          # for the keyring, then u2f / fprintd as the sufficient 2nd factor.
          rules.auth = {
            "unix-early".enable = lib.mkForce false;
            unix = {
              control = lib.mkForce "required";
              order = lib.mkForce 10700;
              settings = {
                nullok = lib.mkForce false;
                try_first_pass = lib.mkForce false;
              };
            };
            gnome_keyring.order = lib.mkForce 10750;
            u2f.order = lib.mkForce 10800;
          };
        };
        greetd =
          if greetdEnabled
          then {
            u2fAuth = true;
            # TODO: disable this asap
            use2Factor = true;
          }
          else {};
        swaylock = {
          u2fAuth = true;
          use2Factor = false;
        };
      };
    };
  };
}
