{ config, lib, ... }:
let
  cfg = config.local.nixAccessTokens;
in {
  options.local.nixAccessTokens.enable =
    lib.mkEnableOption "github.com access-tokens for nix, from a sops secret";

  config = lib.mkIf cfg.enable {
    # Dedicated reader group so the rendered fragment is not world- or
    # users-group-readable. michael is the only member.
    users.groups.nix-tokens = { };
    users.users.michael.extraGroups = [ "nix-tokens" ];

    # Raw token. Stays root:root 0400; only the rendered template below is
    # group-readable. The placeholder keeps the real value out of the store.
    sops.secrets."github-token" = { };

    # nix.conf fragment: access-tokens = github.com=<token>
    sops.templates."nix-access-tokens.conf" = {
      content = "access-tokens = github.com=${config.sops.placeholder."github-token"}";
      group = "nix-tokens";
      mode = "0440";
    };

    # !include is the only thing baked into /etc/nix/nix.conf; both root's
    # nixos-rebuild and the user's home-manager read it via the global config.
    nix.extraOptions = ''
      !include ${config.sops.templates."nix-access-tokens.conf".path}
    '';
  };
}
