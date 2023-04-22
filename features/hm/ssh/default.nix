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
          # local ryzen server prev known as zeus
          # local ip is 192.168.5
          "kore" = mkHost { hostname = "172.30.0.5"; };
          # aarch64 master node prev known as atlas
          "hades" = mkHost { hostname = "172.30.0.4"; };
          # in-progress
          "khaos-rescue" = mkHost {
            hostname = "172.30.0.20";
            user = "root";
            port = 2222;
          };
        };
      };
    };
  };
}