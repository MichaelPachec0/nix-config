{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
} @ args: let
in {
  imports = [];
  config = {
    nix.gc = {
      automatic = true;
      options = "--delete-older-than 7d";
      dates = "daily";
    };

    services.kmonad = {
      enable = true;
      keyboards = {
        laptop-internal = {
          # TODO: change path
          device = "/dev/input/by-path/platform-i8042-serio-0-event-kbd";
          defcfg = {
            enable = true;
            fallthrough = true;
          };
          config = ''
            (defsrc ;; Default keymap for laptop
              esc   f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12  prnt  ins  del
              `     1    2    3    4    5    6    7    8    9    0    -    =    bspc
              tab   q    w    e    r    t    y    u    i    o    p    [    ]    \
              caps  a    s    d    f    g    h    j    k    l    ;    '    ret
              lsft  z    x    c    v    b    n    m    ,    .    /    rsft up
              lctl  lmet lalt           spc            ralt rctl left down right
            )
            (deflayer qwerty ;; Default layer, just switched caps for esc, lctl for caps, and esc for lctl
              caps   f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12  prnt  ins  del
              `     1    2    3    4    5    6    7    8    9    0    -    =    bspc
              tab   q    w    e    r    t    y    u    i    o    p    [    ]    \
              @cen  a    s    d    f    g    h    j    k    l    ;    '    ret
              @lcdt z    x    c    v    b    n    m    ,    .    /    @rcdt up
              esc  lalt lmet           spc            ralt rctl left down right
            )
            (defalias
              ;; cen (tap-next esc lctl)
              ;; tap = esc
              ;; double tap = esc + : (for neovim to enter command mode)
              ;; held + key = ctrl + key
              ;; held > 200ms = ctrl
              ;; cen (tap-hold-next 200 (tap-next esc (tap-macro-release esc : :delay 2)) lctl)
              cen (tap-next esc lctl)
              ;; hel
              ;; simple cadet keys, would like in the future to be able make this a tap dance
              ;; more expansive cadet keys, when tapped once its a ( or ), double tapped { or } held shift, held for 200ms and then released shift.
              lcdt (tap-next  \(  lsft )
              rcdt (tap-next  \)  rsft )
              acrtl ( tap-next a lctl )
              smet ( tap-next s lmet )
              dalt ( tap-next d lalt )
              fshift (tap-next f lsft )

              jshift (tap-next f rsft )
              ;; kalt (tap-next )
              ;; lcdt (tap-hold-next 200 (tap-next \( { ) lsft )
              ;; rcdt (tap-hold-next 200 (tap-next \) } ) rsft )

            )
          '';
        };
      };
    };
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    # home-manager.users.michael = ../../hm/home.nix;
  };
}
