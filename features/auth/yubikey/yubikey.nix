{ config, pkgs, lib, ... }:
let
  # keys [in order] =  799, 718, 838, 828.
  # This is fine to keep in plaintext since the private bits are on the yubikey themselves.
  u2f_keys =
    "michael:DhrurLkHDQCpgSdzh7CPgMNgb+tQ2uDh/5WqixOldGr75ixKMNohH4l+TXghK66MetkjHKxF/iCm6t9Jb2N6rA==,3FHox1tsrKjs3HGn4RWNXvwWiXW0M9kgY0zC2r2fJy7Q9squKei6mvrUfkMzCAWzmmiIKjjZjKmMF5BtxgyswA==,es256,+presence:wgLH6pLDQwlL/RbQnT/CtMuSFn7VH14qQLqkex1t9VsZRCcUMqaaiyqEjsmdAOxuXp9QBKZIXFLAhs/9McmZJQ==,+1u7ifuqoxjSIlCrY7vzF5uI1uhWiNGE39kv0tjjk+PoozygIQHi2CIB4hUDv9WXTPcJk4MhGiFSwGgwSecmhA==,es256,+presence:afjG830wh8QnGsZmb8raLQ5CP3RvXVyKhZBK1e8p8JHvcZHjrIkE8xQifHkjmKqTFL58EUGtePhotzfo9pjOaw==,9hyR6kqSYa3B1nNzpDywlzLVlKXFsEGNbx212VhS34IijOsQTX0o8NQkk+5Q/amQR/hS1UsRcTMx2Q/sxWgGfg==,es256,+presence:6JSCUKfEYEfv7lh4SUTfcrbaxmjD6DnlBMyD25z8MVuO1f9fQaKiaPKTxOtD8u2gUibi4tRUcj8BuUFiwumGhA==,UD90YpoXfGvHcjYBieOWcBmTp5IGoYbpsIAmcjE5chGFDAskKjCXLpxYilwKl7R/ZL9z9uUUqUuFmtdESB4eag==,es256,+presence";

  u2f_file = pkgs.writeText "u2f_mapping" u2f_keys;
  graphical = config.xdg.portal.enable;
  greetdEnabled = config.services.greetd.enable;
in {
  imports = [ ../pam/pam-u2f.nix ];
  config = lib.mkIf (config.yubikey.enable) {
    programs = {
      gnupg.agent = {
        enable = true;
        # use gnupg's ssh support agent instead.
        enableSSHSupport = true;
        enableExtraSocket = true;
        # This is the builtin pinentry app in gnupg
        pinentryFlavor = if (graphical) then "gtk2" else "curses";
      };
    };
    services = {
      dbus.enable = true;
      # smartcard daemon
      pcscd.enable = true;
      # udev rules to access the yubikey
      udev.packages = [ pkgs.yubikey-personalization ];
    };
    enviroment.systemPackages = with pkgs;
      [ yubico-piv-tool yubikey-manager ] ++ lib.optionals (graphical) [
        yubikey-personalization-gui
        yubikey-manager-qt
      ];
    security.pam = {
      u2f = {
        enable = true;
        authFile = "${u2f_file}";
        cue = true;
      };
      services = {
        sudo = {
          u2fAuth = true;
          use2Factor = false;
        };
        login = {
          u2fAuth = true;
          use2Factor = true;
        };
        greetd = if (greetdEnabled) then {
          u2fAuth = true;
          use2Factor = true;
        } else
          { };
      };
    };
  };
}
