{ ... }:
let
  identityFile = [ "~/.ssh/id_ed25519_sk_828" "~/.ssh/id_ed25519_sk_718" ];
  mkHost = { hostname, user ? "sysadm", port ? 22
    , extraOptions ? { PreferredAuthentications = "publickey"; } }: {
      inherit hostname identityFile user port extraOptions;
      identitiesOnly = true;
    };

in {
  imports = [ ];
  options = { };
  config = {
    programs = {
      ssh = {
        enable = true;
        compression = true;
        matchBlocks = {
          "github.com" = mkHost {
            hostname = "github.com";
            user = "git";
          } // {
            #extraOptions = { MACs = "hmac-sha2-512"; };
          };
          # Mac-Pro
          # will look into setting either Match or proxy command
          # https://unix.stackexchange.com/a/175395 < match
          # https://unix.stackexchange.com/a/175465 < proxycommand
          # internal hostname = 192.168.1.3
          "saturn" = mkHost {
            hostname = "172.30.0.2";
            user = "michael";
          };
          # Cloud node referred as gaia on rhel 
          "khaos" = mkHost {
            hostname = "172.30.0.20";
            user = "sysadm";
            extraOptions = {
              RequestTTY = "force";
              PreferredAuthentications = "publickey";
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
          };
          # local ryzen server prev known as zeus
          # local ip is 192.168.1.5
          "kore" = mkHost { hostname = "172.30.0.5"; };
          "decrypt@kore" = mkHost {
            hostname = "192.168.1.5";
            user = "root";
            port = 2222;
          };
          "deploy@kore" = mkHost {
            hostname = "172.30.0.5";
            user = "deploy";
          };
          # aarch64 master node prev known as atlas
          "hades" = mkHost { hostname = "172.30.0.4"; };
        };
      };
    };
  };
}
