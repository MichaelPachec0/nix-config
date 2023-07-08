{ config, pkgs, lib, ... }:
with lib;
let cfg = config.services.systemd-lock-handler;
in {
  options.services.systemd-lock-handler = {
    enable = mkEnableOption (lib.mdDoc "systemd-lock-handler");
    package = mkOption {
      default = pkgs.systemd-lock-handler;
      defaultText = literalExpression "pkgs.systemd-lock-handler";
      type = types.package;
      description = lib.mdDoc "systemd-lock-handler package to use.";
    };
  };
  config = mkIf cfg.enable {
    systemd.user = {
      targets = {
        lock = {
          conflicts = [ "unlock.target" ];
          description = "Lock the currrent session";
        };
        unlock = {
          conflicts = [ "lock.target" ];
          description = "Unlock the currrent session";
        };
        sleep = {
          description =
            "User-level target triggered when the system is about to sleep";
          requires = [ "lock.target" ];
          after = [ "lock.target" ];
        };
      };
      services.systemd-lock-handler = {
        description = "Logind lock event to systemd target translation";
        unitConfig.documentation =
          "https://sr.ht/~whynothugo/systemd-lock-handler";
        serviceConfig = {
          Slice = [ "session.slice" ];
          ExecStart = "${cfg.package}/bin/systemd-lock-handler";
          Type = "notify";
          Restart = "on-failure";
          RestartSec = "10s";
        };
        wantedBy = [ "default.target" ];
      };
    };
  };
}
