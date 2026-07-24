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
  ipAddress = "152.70.124.65";
  keys = import ../../helpers/keys.nix;
  # affine-server, patched to ship an empty app/src. NestJS regenerates the GraphQL
  # schema to ${projectRoot}/src/schema.gql on every start; projectRoot is derived
  # from import.meta.url (= this read-only bundle), so it can't be redirected. We
  # bind a tmpfs over /app/src (below), but systemd can't create that mountpoint
  # under the read-only store -- so the package must ship the empty dir. Folded into
  # flake-playground's affine-server.nix for the next pin bump (then drop this).
  affinePackage =
    (inputs.flake-playground.packages.${pkgs.stdenv.hostPlatform.system}.affine-server).overrideAttrs
    (old: {
      postInstall = (old.postInstall or "") + "mkdir -p $out/app/src\n";
    });
  # Bundled prisma engines (prisma 6.6, linux-arm64-openssl-3.0.x) shipped in the
  # affine-server image and autopatchelfed for NixOS. nixpkgs' prisma-engines is
  # 7.8 (major-incompatible), so the services must point at these instead.
  prismaEngines = "${affinePackage}/app/node_modules/@prisma/engines";
  prismaQueryLib = "${prismaEngines}/libquery_engine-linux-arm64-openssl-3.0.x.so.node";
  prismaSchemaEngine = "${prismaEngines}/schema-engine-linux-arm64-openssl-3.0.x";
  # The module's managed/peer-auth DATABASE_URL uses the libpq empty-host socket
  # form (postgresql://affine@/affine?host=/run/postgresql), which prisma rejects
  # (P1013 "empty host"). Prisma needs a dummy `localhost` authority; the `host=`
  # socket dir still wins. TODO: fix in the flake-playground affine module.
  affineDbUrl = "postgresql://${config.services.affine.database.user}@localhost/${config.services.affine.database.name}?host=/run/postgresql";
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
    # Self-hosted AFFiNE (services.affine). aarch64 package + module come from
    # flake-playground; the input is pinned in the repo flake.lock.
    inputs.flake-playground.nixosModules.affine
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
      serviceConfig = let
        # test = pkgs.writeShellScriptBin "tuwunel-wrapper" ''
        #   # echo $CREDENTIALS_DIRECTORY
        #   # ls $CREDENTIALS_DIRECTORY/token
        #   # cat $CREDENTIALS_DIRECTORY/token
        #   # cat $TOKEN
        #   # sha256sum $CREDENTIALS_DIRECTORY/token
        #   # sha256sum $TOKEN1
        #   # sha256sum $(cat $CREDENTIALS_DIRECTORY/token)
        #   ${lib.getExe inputs.tuwunel.packages.${pkgs.stdenv.hostPlatform.system}.default} -O registration_token_file=\"$CREDENTIALS_DIRECTORY/token\"
        # '';
      in {
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
        # Dedicated EXACT-MATCH cert for affine (no wildcard). The AFFiNE Android
        # app fails auth ("Invalid Password") when the served cert is a wildcard
        # (upstream bug, issue #13397). Requires grey-clouding (DNS-only) the affine
        # record in Cloudflare so the app reaches this origin cert directly rather
        # than Cloudflare's (wildcard) edge cert. DNS-01 works regardless of proxy.
        "affine.michaelpacheco.org" = {
          webroot = null; # cancel the webroot the vhost's enableACME injects (DNS-01 only)
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
        kumaPort = config.services.uptime-kuma.settings.PORT;
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
        "affine.michaelpacheco.org" = {
          # Dedicated exact-match cert (see security.acme.certs above) instead of the
          # *.michaelpacheco.org wildcard — the AFFiNE Android app rejects wildcard
          # certs. Requires the affine DNS record be grey-clouded (DNS-only) so the
          # app hits this origin cert, not Cloudflare's wildcard edge cert.
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://${config.services.affine.host}:${toString config.services.affine.port}";
            proxyWebsockets = true; # AFFiNE realtime doc-sync uses WebSockets
            # recommendedProxySettings (global default) already sets AFFiNE's headers
            # — Host $host, X-Real-IP, X-Forwarded-For/Proto — so only the upload cap
            # is left. (AFFiNE's example shows Host $http_host, but gixy mandates
            # $host; equivalent here, esp. under HTTP/2 where both derive from :authority.)
            extraConfig = "client_max_body_size 100M;"; # allow blob/attachment uploads
          };
        };
        "mealie.michaelpacheco.org" = {
          # Reuse the existing *.michaelpacheco.org wildcard cert (issued under the
          # atuin.michaelpacheco.org ACME entry) rather than requesting a new one.
          useACMEHost = "atuin.michaelpacheco.org";
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.mealie.port}";
            proxyWebsockets = true; # AFFiNE realtime doc-sync uses WebSockets
            extraConfig = "client_max_body_size 100M;"; # allow blob/attachment uploads
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
      # aarch64 qemu emulation makes build-time Python test suites unreliable here:
      # paho-mqtt's broker tests race (via the installCheck phase), and mealie's
      # OWN pytestCheckPhase SIGABRTs/core-dumps under emulation. Disable checks for
      # both (doCheck + doInstallCheck) — these are package-time tests and don't
      # affect runtime. Scoped to mealie's python3 and mealie itself, so the global
      # set is untouched (only mealie + paho-mqtt rebuild).
      package =
        (pkgs.mealie.override {
          python3 = pkgs.python3.override {
            packageOverrides = _: pyprev: {
              paho-mqtt = pyprev.paho-mqtt.overridePythonAttrs (_: {
                doCheck = false;
                doInstallCheck = false;
              });
            };
          };
        }).overridePythonAttrs (_: {
          doCheck = false;
          doInstallCheck = false;
        });
    };
    services.uptime-kuma = {
      enable = true;
      settings = {
        PORT = "4000";
      };
    };
    programs.neovim.package = lib.mkForce pkgs.neovim-unwrapped;

    services.affine = {
      enable = true;
      package = affinePackage; # ships an empty app/src for the schema tmpfs bind
      externalUrl = "https://affine.michaelpacheco.org";
      # host = 127.0.0.1, port = 3010 (defaults) — correct behind nginx.
      # database.manage / redis.manage default true: own DB+role+pgvector in the
      # existing PG cluster, and a dedicated redis-affine instance.
      admin = {
        email = "michaelpacheco@protonmail.com"; # your AFFiNE admin login
        passwordFile = config.sops.secrets."affine/admin-login-password".path;
      };
      # Non-secret SMTP settings (purelymail). The password is injected via
      # EnvironmentFile below so it never lands in the Nix store.
      extraEnvironment = {
        MAILER_HOST = "smtp.purelymail.com";
        MAILER_PORT = "465"; # implicit TLS; nodemailer auto-secures 465
        MAILER_SECURE = "true";
        MAILER_USER = "affine@michaelpacheco.org"; # TODO: your purelymail sending mailbox
        MAILER_SENDER = "affine@michaelpacheco.org"; # TODO: same/aliased sender address
      };
    };
    # SMTP password. The sops secret's plaintext MUST be the single line
    #   MAILER_PASSWORD=<purelymail password>
    # (systemd EnvironmentFile is KEY=value, not a bare secret).
    systemd.services.affine.serviceConfig.EnvironmentFile =
      config.sops.secrets."affine/email-password".path;

    # affine-server's self-host-predeploy.js shells out to `yarn prisma migrate
    # deploy` / `yarn cli run`, but the Path-B package doesn't ship yarn -> the
    # migration dies with "yarn: command not found" (status 127). Provide classic
    # yarn (matches the upstream node:22 base image; node-modules linker means
    # `yarn prisma` just runs node_modules/.bin/prisma) plus the package's own node
    # (prisma's `env node` shebang + its autopatchelfed native query engine).
    # TODO: fold this into the flake-playground affine module so it's fixed upstream.
    systemd.services.affine-migrate.path = [
      config.services.affine.package.nodejs
      pkgs.yarn
    ];

    # Prisma can't auto-detect/download engines on NixOS (read-only store, platform
    # detected as "nixos"), so hand it the bundled ones explicitly. The module runs
    # `node <script>` directly and bypasses the package bin-wrapper, so nothing sets
    # PRISMA_QUERY_ENGINE_LIBRARY otherwise. Migrate additionally needs the schema
    # (migration) engine. See prismaEngines/* above. TODO: fold into the module.
    systemd.services.affine-migrate.environment = {
      PRISMA_SCHEMA_ENGINE_BINARY = prismaSchemaEngine;
      PRISMA_QUERY_ENGINE_LIBRARY = prismaQueryLib;
      # prisma-compatible socket URL (overrides the module's empty-host form).
      DATABASE_URL = lib.mkForce affineDbUrl;
    };
    systemd.services.affine.environment = {
      PRISMA_QUERY_ENGINE_LIBRARY = prismaQueryLib;
      DATABASE_URL = lib.mkForce affineDbUrl;
    };
    # NestJS regenerates the GraphQL schema to `${projectRoot}/src/schema.gql` on
    # every start. projectRoot is derived from import.meta.url (= the read-only
    # /app bundle), so it can't be redirected -> EROFS. It's a regenerated artifact,
    # so bind an ephemeral tmpfs over /app/src. TODO: bake this into the package.
    systemd.services.affine.serviceConfig.RuntimeDirectory = "affine-schema";
    systemd.services.affine.serviceConfig.BindPaths = [
      "/run/affine-schema:${config.services.affine.package}/app/src"
    ];

    # Recover sysadmin's password. base.nix sets an invalid placeholder hash and
    # mutableUsers = false, so it can't be fixed at runtime — override it here with
    # the sops-managed hash. Store it under the `selene:` MAP (like the other
    # selene/* secrets); sops-nix walks maps at any depth but NOT the old `users:`
    # LIST entry. Create secrets/default.yaml -> selene.sysadmin.password before
    # deploying.
    users.users.sysadmin.hashedPassword = lib.mkForce null;
    users.users.sysadmin.hashedPasswordFile =
      config.sops.secrets."users/sysadmin/password".path;

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
      # AFFiNE: admin login password (raw) + mailer env-file (MAILER_PASSWORD=...).
      # Read by systemd as root (LoadCredential / EnvironmentFile), so no owner.
      "affine/admin-login-password" = {};
      "affine/email-password" = {};
      # sysadmin login hash — neededForUsers so it's decrypted before user setup
      # (required with mutableUsers = false).
      "users/sysadmin/password" = {neededForUsers = true;};
      "dummy-token" = {};
    };
  };
}
