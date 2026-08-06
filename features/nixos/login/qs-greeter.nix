{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.qsGreeter;
in {
  options.programs.qsGreeter = {
    enable = lib.mkEnableOption "the Quickshell greetd greeter";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.qs-greeter;
      description = "The QML tree installed as the greeter config.";
    };

    precedence = lib.mkOption {
      type = lib.types.enum ["user" "nix"];
      default = "user";
      description = ''
        Which tier wins for cosmetic keys. "user" lets the writable settings
        file override the values set here; "nix" ignores that file entirely.
      '';
    };

    skin = lib.mkOption {
      type = lib.types.str;
      default = "xp";
      description = "Default skin name. Overridable by the user tier.";
    };

    skins.extra = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Additional skins to register. PRIVILEGED: a skin is QML executed in the
        pre-auth greeter process, so skins may only be added here, never from
        the writable settings file.
      '';
    };

    skinSettings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {xp = {palette = "luna";};};
      description = "Per-skin cosmetic defaults, namespaced by skin name.";
    };

    backdrop = {
      kind = lib.mkOption {
        type = lib.types.enum ["color" "image"];
        default = "color";
        description = "Backdrop source.";
      };
      color = lib.mkOption {
        type = lib.types.str;
        default = "#3A6EA5";
        description = "Backdrop color when kind = color.";
      };
      image = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Basename of an image under backdropDir. A basename, not a path:
          values containing "/" are rejected at load time.
        '';
      };
      fit = lib.mkOption {
        type = lib.types.enum ["cover" "contain" "fill" "tile"];
        default = "cover";
        description = "How the backdrop image covers the output.";
      };
    };

    sessions = {
      picker = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show the session row behind the Options button.";
      };
      filter = lib.mkOption {
        type = lib.types.enum ["uwsm" "all"];
        default = "uwsm";
        description = ''
          "uwsm" keeps only *-uwsm.desktop wayland sessions; "all" keeps every
          session found.
        '';
      };
      shells = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [pkgs.zsh pkgs.bashInteractive];
        description = "Shell sessions appended after the graphical ones.";
      };
      extra = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {type = lib.types.str;};
            argv = lib.mkOption {type = lib.types.listOf lib.types.str;};
            env = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = {};
            };
          };
        });
        default = [];
        description = "Hand-written session entries, inserted before shells.";
      };
    };

    userFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/qs-greeter/settings.json";
      description = "Group-writable cosmetic settings file.";
    };

    backdropDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/qs-greeter/backdrops";
      description = "Only directory the greeter will load backdrop images from.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "qsgreeter";
      description = "Group allowed to write the user settings tier.";
    };

    logging = {
      level = lib.mkOption {
        type = lib.types.ints.between 0 2;
        default = 2;
        description = "0 none, 1 = -v (INFO), 2 = -vv (DEBUG).";
      };
      rules = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Passed to --log-rules (QT_LOGGING_RULES syntax).";
      };
      timestamps = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Pass --log-times.";
      };
      dir = lib.mkOption {
        type = lib.types.str;
        default = "/var/log/qs-greeter";
        description = "Where per-run log files are written.";
      };
      keep = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10;
        description = "How many past run logs to retain.";
      };
      journal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Also tee output to the journal as qs-greeter.";
      };
      showOnFallback = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show a log tail on the crash-loop fallback screen.";
      };
    };

    crashLoop = {
      threshold = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        description = "Starts within the window before the fallback engages.";
      };
      window = lib.mkOption {
        type = lib.types.ints.positive;
        default = 120;
        description = "Seconds counted for the crash-loop threshold.";
      };
    };

    auth = {
      backoff = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Apply the delay/lockout escalation below (free/start/max) on
            repeated auth failures. Off by default: a wrong password is
            always immediately retryable, with no delay and no lockout, no
            matter how many attempts are made. The original always-on
            design tracked failures in a single counter shared across every
            username, which turned out to be trivially bypassed by
            alternating the attempted username between guesses -- each
            login attempt with a different name reset the counter to zero,
            so the lockout never engaged (reproduced 5/5 in testing). Left
            off until a caller picks a mode below that actually matches
            their threat model; see perUser.
          '';
        };
        perUser = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            When backoff is enabled, track failures and lockout per
            attempted username instead of in one counter shared by every
            name typed at the greeter. The shared counter (perUser = false,
            the plan's original behavior, kept available for callers who
            still want it) resets whenever the typed username changes, so
            alternating between a real account and a throwaway name on
            every attempt keeps the counter pinned near zero and defeats
            the lockout entirely. perUser tracking keys failures and
            blockedUntil to the username being attempted, so repeated
            guesses against one account accumulate against that account no
            matter what else is typed in between -- this is the mode that
            actually resists the alternate-the-username bypass, at the
            cost of a small amount of state kept per distinct username
            seen. Off by default alongside enable; both need to be turned
            on together to get a lockout that resists that bypass.
          '';
        };
        free = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 3;
          description = "Failures allowed before delays begin.";
        };
        start = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = "First delay in seconds; doubles each failure.";
        };
        max = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10;
          description = "Delay ceiling in seconds.";
        };
      };
      idleTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 60;
        description = "Seconds before an idle authenticating session cancels.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${cfg.group} = {};

    systemd.tmpfiles.rules = [
      "d /var/lib/qs-greeter 0755 greeter ${cfg.group} - -"
      "d ${cfg.backdropDir} 0775 greeter ${cfg.group} - -"
      "d ${cfg.logging.dir} 0750 greeter greeter - -"
      "f ${cfg.userFile} 0664 greeter ${cfg.group} - -"
    ];

    environment.systemPackages = [cfg.package];
  };
}
