{...}: let
  identityFile = [
    "~/.ssh/id_ed25519_sk_799"
    "~/.ssh/id_ed25519_sk_766"
    "~/.ssh/id_ed25519_sk_828"
    "~/.ssh/id_ed25519_sk_718"
    "~/.ssh/id_ed25519_sk_791"
  ];
  mkHost = {
    hostname,
    user ? "sysadmin",
    port ? 22,
    options ? {},
  }: {
    inherit hostname identityFile user port;
    extraOptions = {PreferredAuthentications = "publickey";} // options;
    identitiesOnly = true;
  };
in {
  imports = [];
  options = {};
  config = {
    programs = {
      ssh = {
        enable = true;
        compression = true;
        matchBlocks = {
          "github.com" =
            mkHost {
              hostname = "github.com";
              user = "git";
            }
            // {
              #options = { MACs = "hmac-sha2-512"; };
            };
          # Mac-Pro
          # will look into setting either Match or proxy command
          # https://unix.stackexchange.com/a/175395 < match
          # https://unix.stackexchange.com/a/175465 < proxycommand
          # internal hostname = 192.168.1.3
          "saturn" = mkHost {
            hostname = "172.30.0.2";
            # hostname = "192.168.1.3";
            user = "michael";
            options = {ForwardAgent = "yes";};
          };
          "saturn_local" = mkHost {
            # hostname = "172.30.0.2";
            hostname = "192.168.1.3";
            user = "michael";
            options = {ForwardAgent = "yes";};
          };
          # Cloud node referred as gaia on rhel
          # WARN: DEPRECATED.
          "khaos" = mkHost {
            hostname = "172.30.0.20";
            user = "sysadm";
            options = {
              ForwardAgent = "yes";
              RequestTTY = "force";
            };
          };
          # in-progress
          "rescue@khaos" = mkHost {
            hostname = "172.30.0.20";
            user = "root";
            port = 2222;
          };
          # kvm
          "charon" = mkHost {
            hostname = "172.30.0.8";
            user = "root";
            options = {ForwardAgent = "yes";};
          };
          # local ryzen server prev known as zeus
          # local ip is 192.168.1.5
          "kore" = mkHost {
            hostname = "172.30.0.5";
            options = {ForwardAgent = "yes";};
          };
          "kore_local" = mkHost {
            hostname = "192.168.1.5";
            options = {ForwardAgent = "yes";};
          };
          "decryptATkore" = mkHost {
            hostname = "192.168.1.5";
            user = "root";
            port = 2222;
          };
          "deployATkore" = mkHost {
            hostname = "172.30.0.5";
            user = "deploy";
          };
          # aarch64 master node prev known as atlas
          "hades" = mkHost {hostname = "172.30.0.4";};
          # vm: local ip is 192.168.1.8
          "odin" = mkHost {hostname = "172.30.0.11";};
          # TODO: include OC instances.
          selene = mkHost {hostname = "152.70.124.65";};
          nyx = mkHost {
            hostname = "172.30.0.7";
            user = "michael";
            options = {ForwardAgent = "yes";};
          };
          thanatos = mkHost {
            hostname = "172.30.0.23";
            user = "michael";
            options = {ForwardAgent = "yes";};
          };
          "deployATselene" = mkHost {
            hostname = "152.70.124.65";
            user = "deploy";
          };
          atlas = mkHost {
            hostname = "142.171.216.47";
            options = {ForwardAgent = "yes";};
          };
          "deployATatlas" = mkHost {
            hostname = "142.171.216.47";
            user = "deploy";
          };
          "decryptATatlas" = mkHost {
            hostname = "142.171.216.47";
            user = "root";
            port = 2222;
          };
        };
      };
    };
  };
}
