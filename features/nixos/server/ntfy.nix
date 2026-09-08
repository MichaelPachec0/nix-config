# ntfy.sh alert channel shared by the auto-upgrade units.
#
# Provides `ntfy-send TITLE PRIORITY TAGS < body`. The bearer token and the
# topic name are sops secrets delivered to consuming units through
# LoadCredential (see local.ntfy.loadCredential); the topic is treated as a
# secret because on ntfy.sh knowing the topic is enough to subscribe.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.ntfy;
in {
  options.local.ntfy = {
    enable = lib.mkEnableOption "ntfy.sh alert sender with sops-provided token and topic";
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "Wrapper providing bin/ntfy-send.";
    };
    loadCredential = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "LoadCredential entries a consuming unit must set.";
    };
  };

  config = lib.mkIf cfg.enable {
    local.ntfy.package = pkgs.writeShellApplication {
      name = "ntfy-send";
      runtimeInputs = with pkgs; [curl coreutils];
      text = builtins.readFile ./scripts/ntfy-send.sh;
    };
    local.ntfy.loadCredential = [
      "ntfy-token:${config.sops.secrets."ntfy-token".path}"
      "ntfy-topic:${config.sops.secrets."ntfy-topic".path}"
    ];

    sops.secrets."ntfy-token" = {};
    sops.secrets."ntfy-topic" = {};
  };
}
