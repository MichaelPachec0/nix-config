{ config, lib, pkgs, ... }:
let
  cfg = config.services.e5800;
  src = pkgs.runCommand "e5800-src" { } ''
    mkdir -p $out
    cp ${./e5800/e5800lib.py}      $out/e5800lib.py
    cp ${./e5800/e5800_poll.py}    $out/e5800_poll.py
    cp ${./e5800/e5800_recover.py} $out/e5800_recover.py
  '';
  runtimePath = lib.makeBinPath [ pkgs.openssh pkgs.openssl pkgs.iputils pkgs.coreutils ];
  mkBin = name: entry: pkgs.writeShellScriptBin name ''
    export PATH=${runtimePath}:$PATH
    exec ${pkgs.python3}/bin/python3 ${src}/${entry} "$@"
  '';
  pollBin = mkBin "e5800-poll" "e5800_poll.py";
  recoverBin = mkBin "e5800-recover" "e5800_recover.py";
  # Convenience for re-authenticating after a router factory reset: appends the
  # version-controlled e5800poll public key to the router's authorized_keys
  # (prompts for the router admin password), then clears the poll service's
  # pinned host key so it re-trusts the router's new host key on the next poll.
  bareHost = lib.removePrefix "https://" (lib.removePrefix "http://" cfg.host);
  provisionBin = pkgs.writeShellScriptBin "e5800-provision-key" ''
    set -e
    echo "Installing the e5800poll public key on the router at ${bareHost}"
    echo "(enter the router admin password when prompted)"
    ${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile=/dev/null \
      root@${bareHost} 'mkdir -p /etc/dropbear && cat >> /etc/dropbear/authorized_keys' \
      < ${./e5800/e5800poll.pub}
    echo "Key installed. Clearing the poll service's pinned host key (sudo)..."
    sudo rm -f /var/lib/e5800/known_hosts
    echo "Done -- the poll service reconnects on its next cycle."
  '';
  commonEnv = {
    E5800_HOST = cfg.host;
    E5800_USER = cfg.user;
    E5800_SSH_KEY = config.sops.secrets."e5800/ssh_key".path;
    E5800_WEB_PW_FILE = config.sops.secrets."e5800/web_password".path;
    E5800_RUNTIME = "/run/e5800";
    E5800_STATE = "/var/lib/e5800";
    E5800_RESET_DAY = toString cfg.cycleResetDay;
    E5800_NETDEV = cfg.netdev;
  };
  hardening = {
    ProtectHome = true;
    ProtectSystem = "strict";
    NoNewPrivileges = true;
    PrivateTmp = true;
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    SystemCallFilter = [ "@system-service" ];
    CapabilityBoundingSet = [ "" ];
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    RestrictNamespaces = true;
  };
  recoverUnit = action: {
    description = "GL-E5800 modem recovery: ${action}";
    serviceConfig = hardening // {
      Type = "oneshot";
      User = "e5800poll";
      Group = "e5800poll";
      ReadWritePaths = [ "/run/e5800" "/var/lib/e5800" ];
      ExecStart = "${recoverBin}/bin/e5800-recover ${action}";
      Environment = lib.mapAttrsToList (k: v: "${k}=${v}") commonEnv;
    };
  };
in
{
  options.services.e5800 = {
    enable = lib.mkEnableOption "GL-E5800 router status poller";
    host = lib.mkOption { type = lib.types.str; default = "http://192.168.8.1"; };
    user = lib.mkOption { type = lib.types.str; default = "root"; };
    cycleResetDay = lib.mkOption { type = lib.types.int; default = 1; };
    netdev = lib.mkOption { type = lib.types.str; default = ""; };
    triggerUser = lib.mkOption { type = lib.types.str; default = "michael"; };
  };

  config = lib.mkIf cfg.enable {
    users.users.e5800poll = {
      isSystemUser = true;
      group = "e5800poll";
      home = "/var/lib/e5800";
    };
    users.groups.e5800poll = { };

    sops.secrets."e5800/ssh_key" = { owner = "e5800poll"; mode = "0400"; };
    sops.secrets."e5800/web_password" = { owner = "e5800poll"; mode = "0400"; };

    environment.systemPackages = [ pollBin recoverBin provisionBin ];

    systemd.services.e5800-poll = {
      description = "GL-E5800 router status poller";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = hardening // {
        User = "e5800poll";
        Group = "e5800poll";
        RuntimeDirectory = "e5800";
        RuntimeDirectoryMode = "0755";
        StateDirectory = "e5800";
        ExecStart = "${pollBin}/bin/e5800-poll --loop";
        Restart = "always";
        RestartSec = 5;
        Environment = lib.mapAttrsToList (k: v: "${k}=${v}") commonEnv;
      };
    };

    systemd.services.e5800-redial = recoverUnit "redial";
    systemd.services.e5800-airplane = recoverUnit "airplane";
    systemd.services.e5800-reboot-modem = recoverUnit "reboot";

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.user == "${cfg.triggerUser}") {
          var unit = action.lookup("unit");
          if (unit == "e5800-redial.service" ||
              unit == "e5800-airplane.service" ||
              unit == "e5800-reboot-modem.service") {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };
}
