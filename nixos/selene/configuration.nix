# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  # TODO: check if this changes!
  keys = import ../../helpers/keys.nix;
in {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../features/nixos/common
    ../../features/nixos/common/deploy.nix
    ../../features/nixos/server
    ../../features/nixos/server/base.nix
    ../../helpers/caches.nix
    # "${inputs.nixpkgs}/nixos/modules/services/matrix/conduwuit.nix"
  ];

  options.services.matrix-conduit.settings = lib.mkOption {
    apply = old:
      old
      // (
        if (old.global ? "unix_socket_path")
        then {global = builtins.removeAttrs old.global ["address" "port"];}
        else {}
      );
  };
  config = {
    # Use the systemd-boot EFI boot loader.
    boot = {
      loader = {
        systemd-boot.enable = true;
        efi = {
          canTouchEfiVariables = true;
          efiSysMountPoint = "/boot";
        };
      };
      initrd.systemd.enable = true;
      kernelParams = [
        "boot.shell_on_fail"
      ];
    };
    networking = {
      hostName = "selene";
      networkmanager.enable = true;
      firewall = {
        enable = true;
        allowedTCPPortRanges = [];
        allowedTCPPorts = [
          80
          443
        ];
        allowedUDPPortRanges = let
          coturn = with config.services.coturn; {
            from = min-port;
            to = max-port;
          };
        in [
          coturn
        ];
        allowedUDPPorts = [
          80
          443
        ];
      };
    };

    zramSwap = {
      memoryPercent = 30;
    };
    users.users.sysadmin = {
      openssh.authorizedKeys.keys = keys.laptops;
    };

    services.eternal-terminal.enable = true;
    environment.systemPackages = with pkgs; [
      # vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
      # wget
      direnv
      swtpm
      git
      btop
      fastfetch
    ];
    services.coturn = {
      enable = false;
      no-cli = true;
      no-tcp = true;
      min-port = 49000;
      max-port = 50000;
      # use-auth-secret = "";
      extraConfig = ''
        # for debugging
        verbose
        # ban private IP ranges
        no-multicast-peers
        denied-peer-ip=0.0.0.0-0.255.255.255
        denied-peer-ip=10.0.0.0-10.255.255.255
        denied-peer-ip=100.64.0.0-100.127.255.255
        denied-peer-ip=127.0.0.0-127.255.255.255
        denied-peer-ip=169.254.0.0-169.254.255.255
        denied-peer-ip=172.16.0.0-172.31.255.255
        denied-peer-ip=192.0.0.0-192.0.0.255
        denied-peer-ip=192.0.2.0-192.0.2.255
        denied-peer-ip=192.88.99.0-192.88.99.255
        denied-peer-ip=192.168.0.0-192.168.255.255
        denied-peer-ip=198.18.0.0-198.19.255.255
        denied-peer-ip=198.51.100.0-198.51.100.255
        denied-peer-ip=203.0.113.0-203.0.113.255
        denied-peer-ip=240.0.0.0-255.255.255.255
        denied-peer-ip=::1
        denied-peer-ip=64:ff9b::-64:ff9b::ffff:ffff
        denied-peer-ip=::ffff:0.0.0.0-::ffff:255.255.255.255
        denied-peer-ip=100::-100::ffff:ffff:ffff:ffff
        denied-peer-ip=2001::-2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff
        denied-peer-ip=2002::-2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff
        denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
        denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
      '';
    };
    services.matrix-conduit = {
      enable = true;
      package = inputs.tuwunel.packages.${pkgs.stdenv.hostPlatform.system}.default;
      settings = {
        global = {
          # allow_check_for_updates = true;
          server_name = "smatrix.root.sx";
          allow_registration = true;
          require_auth_for_profile_requests = true;
          allow_public_room_directory_over_federation = true;
        };
      };
    };
    systemd.services.conduit = {
      # environment = {
      #   "TOKEN1" = "%d/token";
      # };
      serviceConfig = {
        LoadCredential = "token:${config.sops.secrets."selene/conduwuit/registration_token".path}";
        ExecStart = lib.mkForce ''
          ${lib.getExe inputs.tuwunel.packages.${pkgs.stdenv.hostPlatform.system}.default} -O registration_token_file=\"%d/token\"
        '';
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = "ng66lkpjl@mozmail.com";
      certs = {
        "selene.root.sx" = {
          webroot = "/var/lib/acme/.challenges";
          # Ensure that the web server you use can read the generated certs
          # Take a look at the group option for the web server you choose.
          # group = "nginx";
          # Since we have a wildcard vhost to handle port 80,
          # we can generate certs for anything!
          # Just make sure your DNS resolves them.
          # extraDomainNames = [ "mail.example.com" ];
        };
        "smatrix.root.sx" = {
          webroot = "/var/lib/acme/.challenges";
        };
        "atuin.michaelpacheco.org" = {
          domain = "michaelpacheco.org";
          webroot = null;
          extraDomainNames = ["*.michaelpacheco.org"];
          dnsProvider = "cloudflare";
          dnsResolver = "1.1.1.1:53";
          dnsPropagationCheck = true;
          environmentFile = config.sops.secrets."cloudflare-dns-token".path;
        };
      };
    };
    users.users.nginx.extraGroups = ["acme"];

    services.nginx = {
      enable = true;

      # WARN: do not enable until successful acme install
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;

      virtualHosts = let
        matrixPort = config.services.matrix-conduit.settings.global.port;
        atuinPort = config.services.atuin.port;
        matrixHost = "http://localhost:${toString matrixPort}";
      in {
        # "${ipAddress}" = {
        #   locations = {
        #     "/" = {
        #       return = "302 https://feetfinder.com";
        #     };
        #   };
        # };
        # "selene.eu.org" = {
        #   locations = {
        #     "/" = {
        #       return = "302 https://feetfinder.com";
        #     };
        #   };
        # };
        "acmechallenge.selene.root.sx" = {
          # WARN: This is eww
          serverAliases = ["*.selene.root.sx" "smatrix.root.sx"];
          locations."/.well-known/acme-challenge" = {
            root = "/var/lib/acme/.challenges";
          };
          # WARN: so is this
          onlySSL = false;
          locations."/" = {
            return = "301 https://$host$request_uri";
          };
        };
        "selene.root.sx" = {
          enableACME = true;

          # WARN: do not enable until successful acme install
          # This might be need to be disabled initially to get passed errors
          onlySSL = true;

          locations = {
            "/" = {
              root = "/srv/root";
              extraConfig = ''
                add_header Content-Type text/html;
              '';
            };
            "^~ /.well-known/matrix".proxyPass = matrixHost;
            "/secret/estevan" = {
              # root = "/srv/root/";
              root = "/srv/root";
              basicAuthFile = config.sops.secrets."selene/nginx/estevan".path;
              extraConfig = ''
                autoindex on;
                autoindex_exact_size off;
                autoindex_localtime on;
              '';
            };
            "/secret/urbex" = {
              # root = "/home/sysadmin/";
              root = "/srv/root";
              basicAuthFile = config.sops.secrets."selene/nginx/urbex".path;
              extraConfig = ''
                autoindex on;
                autoindex_exact_size off;
                autoindex_localtime on;
              '';
            };
            "/quiz" = {
              root = "/var/www/quizlet/frontend/dist";
            };
          };
        };
        "smatrix.root.sx" = {
          enableACME = true;
          onlySSL = true;
          locations = {
            "^~ /_matrix" = {
              proxyPass = matrixHost;
              recommendedProxySettings = false;
              extraConfig = ''
                proxy_set_header X-ForwardedFor $remote_addr;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header Host $host;
                client_max_body_size 50M;
                proxy_http_version 1.1;
              '';
            };
            "/" = {
              proxyPass = matrixHost;
            };
          };
        };
        "secrets.michaelpacheco.org" = {
          enableACME = true;
          forceSSL = true;
          locations = {
            "/" = {
              return = 404;
              extraConfig = ''
                deny all;
              '';
              # root = "/srv/root/secret/";
            };
            "/urbex" = {
              root = "/srv/root/secret";
              basicAuthFile = config.sops.secrets."selene/nginx/urbex".path;
              extraConfig = ''
                autoindex on;
                autoindex_exact_size off;
                autoindex_localtime on;
              '';
            };
            "/estevan/" = {
              return = 404;
              extraConfig = ''
                deny all;
              '';
            };
          };
        };
        "atuin.michaelpacheco.org" = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString atuinPort}";
            proxyWebsockets = false;
            extraConfig =
              "proxy_ssl_server_name on;"
              + "proxy_pass_header Authorization;";
          };
        };
        # "kuma.michaelpacheco.org" = {
        #   enableACME = true;
        #   forceSSL = true;
        #   locations."/" = {
        #     proxyPass = "http://127.0.0.1:${toString kumaPort}";
        #     proxyWebsockets = false;
        #     extraConfig = ''
        #       proxy_set_header   X-Real-IP $remote_addr;
        #       proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        #       proxy_set_header   Host $host;
        #       proxy_pass         http://localhost:3001/;
        #       proxy_http_version 1.1;
        #       proxy_set_header   Upgrade $http_upgrade;
        #       proxy_set_header   Connection "upgrade";
        #     '';
        #   };
        # };
      };
    };
    services.fail2ban = {
      enable = false;
      # Ban IP after 5 failures
      maxretry = 5;
      ignoreIP = [
        # Whitelist some subnets
        "10.0.0.0/8"
        "172.30.0.0/12"
        "8.8.8.8" # whitelist a specific IP
      ];
      bantime = "24h"; # Ban IPs for one day on the first ban
      bantime-increment = {
        enable = true; # Enable increment of bantime after each violation
        formula = "ban.Time * math.exp(float(ban.Count+1)*banFactor)/math.exp(1*banFactor)";
        multipliers = "1 2 4 8 16 32 64";
        maxtime = "168h"; # Do not ban for more than 1 week
        overalljails = true; # Calculate the bantime based on all the violations
      };
      jails = {
        apache-nohome-iptables.settings = {
          # Block an IP address if it accesses a non-existent
          # home directory more than 5 times in 10 minutes,
          # since that indicates that it's scanning.
          filter = "apache-nohome";
          action = ''iptables-multiport[name=HTTP, port="http,https"]'';
          logpath = "/var/log/httpd/error_log*";
          backend = "auto";
          findtime = 600;
          bantime = 600;
          maxretry = 5;
        };
      };
    };
    services.atuin = {
      enable = true;
      openFirewall = false;
      openRegistration = true;
      port = 8889;
    };
    services.mealie = {
      enable = true;
      listenAddress = "127.0.0.1";
    };
    services.uptime-kuma = {
      enable = true;
      settings = {
        PORT = "4000";
      };
    };

    sops.defaultSopsFile = ../../secrets/default.yaml;
    sops.defaultSopsFormat = "yaml";
    sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    sops.age.keyFile = "/var/lib/sops-nix/key.txt";
    sops.age.generateKey = true;
    sops.secrets = {
      "cloudflare-dns-token" = {};
      "selene/conduwuit/registration_token" = {
        # owner = config.users.users."conduit".name;
        # owner = "conduit";
        # owner = "${config.systemd.services.conduit.serviceConfig.User}";
        # mode = "0440";
      };
      "selene/cloudflare/api-token" = {};
      "selene/nginx/estevan" = {
        owner = config.services.nginx.user;
      };
      "selene/nginx/urbex" = {
        owner = config.services.nginx.user;
      };
      "dummy-token" = {};
    };
  };
}
