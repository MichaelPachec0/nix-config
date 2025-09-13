{
  config,
  pkgs,
  lib,
  ...
}:
# The yubikey-gpg module provides a quick and easy way to setup
# authentication, encryption, and signing with a Yubikey. The module
# assumes you have a Yubikey already set up (see
# https://github.com/drduh/YubiKey-Guide/tree/master for a guide).
#
# Some one-off manual steps are required. For example, if you have a
# Yubikey with one master key (keyid "0x8915C624E4E156A5") and some
# subkeys, plug the Yubikey in, import the public key of the master key:
#
# import-yubikey 0x8915C624E4E156A5
# > Your decision? 5
# > quit
#
# You'll need to do this for each user.
#
# Note that with multiple users, only one can "claim" the Yubikey at a
# time. To use the key with another user, take it out and plug it back
# in again, then run "gpg --card-status" on a user to "claim" it for
# that user.
with lib; let
  cfg = config.hardware.yubikey-gpg;

  # yubikey-touch-detector = pkgs.callPackage ../../../nix/pkgs/yubikey-touch-detector {};

  userSpecificOpts = {config, ...}: {
    options = {
      pinentryFlavor = mkOption {
        type = types.nullOr (types.enum pkgs.pinentry.flavors);
        example = "gnome3";
        description = ''
          Which pinentry interface to use. Pinentry is the program
          which prompts you for your Yubikey pin when required.
        '';
      };
    };
  };

  # TODO: redo all scripts using 
  clearYubikey = pkgs.writeScript "clear-yubikey" ''
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
  options.hardware.yubikey-gpg = {
    enable =
      mkEnableOption
      "Enables yubikey GPG authentication/encryption/signing for a user.";

    users = mkOption {
      default = {};
      example = literalExample ''
        {
          "root".pinentryFlavor = "curses";
          "sam".pinentryFlavor = "gnome3";
        }
      '';
      type = with types; attrsOf (submodule userSpecificOpts);
      description = ''
        Enable yubikey-gpg configuration for a specific user and set
        their configuration options.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      ssh.startAgent = false;
      gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
        enableExtraSocket = true;
        pinentryFlavor = "gtk2";
      };
    };

    environment.systemPackages = with pkgs; [
      gnupg
      yubioath-desktop
      #NOTE: redo this
      # yubikey-manager
      ccid
      importYubikey
      # yubikey-touch-detector
    ];

    services.dbus.enable = true;
    services.pcscd.enable = true;
    services.udev.packages = [pkgs.yubikey-personalization];

    services.udev.extraRules = concatStrings (mapAttrsToList (user: opts: ''
        ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="1050", ATTRS{idProduct}=="0407", RUN+="${
          clearYubikeyUser user
        }"
      '')
      cfg.users);
  };
}
