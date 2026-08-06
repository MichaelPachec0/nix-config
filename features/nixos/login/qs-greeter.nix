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

    wrapperPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      internal = true;
      default = null;
      description = ''
        Computed, not set by callers: the fully-configured launcher greetd
        execs to start the greeter (every QSG_* env var below baked in, then
        exec cfg.package.wrapper). Read by features/nixos/login/default.nix
        to build the /etc/greetd/sway-config exec line when backend =
        "qsGreeter". null whenever the module is disabled -- the regreet
        branch never forces this, so an inactive qs-greeter never needs a
        wrapper built.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${cfg.group} = {};

    systemd.tmpfiles.rules = [
      "d /var/lib/qs-greeter 0755 greeter ${cfg.group} - -"
      "d ${cfg.backdropDir} 0775 greeter ${cfg.group} - -"
      "d ${cfg.logging.dir} 0750 greeter greeter - -"
      "f ${cfg.userFile} 0664 greeter ${cfg.group} - -"
      # State dir for the wrapper's crash counter and generated
      # sessions.json (QSG_STATE_DIR, default /run/qs-greeter, matches
      # Sessions.qml's own default QSG_SESSIONS path -- neither is
      # overridden below, so this rule is the only place that default is
      # spelled out). /run is root:root 0755, so without this the wrapper's
      # own `mkdir -p "$state_dir"`, run as the unprivileged greeter user,
      # would fail on every boot.
      "d /run/qs-greeter 0750 greeter greeter - -"
    ];

    environment.systemPackages = [cfg.package];

    # Cosmetic defaults, rendered from the Nix tier. Valid by construction --
    # it comes from toJSON, not from a parser -- which is why the merge code
    # can treat it as trusted and fall back to it unconditionally.
    environment.etc."qs-greeter/defaults.json".text = builtins.toJSON {
      skin = cfg.skin;
      skins =
        {xp = {palettes = ["luna" "gruvbox"];};}
        // lib.listToAttrs (map (p: {
            name = p.pname or p.name;
            value = {palettes = ["default"];};
          })
          cfg.skins.extra);
      skinSettings = cfg.skinSettings;
      backdrop = {
        inherit (cfg.backdrop) kind color fit;
        image = cfg.backdrop.image;
      };
      sessions = {
        picker = cfg.sessions.picker;
        default = null;
      };
      optionsExpanded = false;
      rememberLastUser = true;
      branding = {
        title = "Log On to Windows";
        subtitle = "Microsoft Windows XP  Professional";
      };
    };

    # The launcher that actually gets exec'd by greetd's sway session. Every
    # QSG_* variable the QML (Settings.qml/Log.qml/Session.qml/Sessions.qml)
    # or the wrapper script itself reads is set here from the matching Nix
    # option -- an unset QSG_* would silently fall back to its hardcoded
    # default in the script, which is a default nobody using this module
    # actually chose. QSG_SESSIONS_DIR, QSG_STATE_DIR/QSG_SESSIONS, and
    # QSG_TTY_HINT are deliberately left unset: none of them has a matching
    # Nix option (session dir is the real wayland-sessions dir; state dir
    # and the TTY hint are plumbing shared verbatim between this script and
    # Sessions.qml/CoreFatal.qml's own hardcoded defaults), so there is
    # nothing here to override.
    programs.qsGreeter.wrapperPackage = let
      bool01 = b: if b then "1" else "0";

      # qs's own verbosity/rule/timestamp flags, distinct from QSG_LOG_LEVEL
      # (which gates our Log.qml singleton's own console.log calls, not
      # Quickshell's engine diagnostics).
      logArgs = lib.concatStringsSep " " (
        lib.optional (cfg.logging.level >= 1) (
          if cfg.logging.level >= 2 then "-vv" else "-v"
        )
        ++ lib.optional (cfg.logging.rules != "")
        "--log-rules ${lib.escapeShellArg cfg.logging.rules}"
        ++ lib.optional cfg.logging.timestamps "--log-times"
      );

      # cfg.sessions.shells is a list of packages (e.g. pkgs.zsh); turn each
      # into the same {name, argv, env} shape sessions-parse.sh emits for
      # graphical sessions, so Sessions.qml never has to special-case them.
      shellSessions = map (shell: {
        name = shell.pname or shell.name;
        argv = [(lib.getExe shell)];
        env = {};
      }) cfg.sessions.shells;
    in
      pkgs.writeShellApplication {
        name = "qs-greeter-launch";
        runtimeInputs = [cfg.package.wrapper];
        text = ''
          export QSG_CONFIG=${cfg.package}/greeter
          export QSG_DEFAULTS=/etc/qs-greeter/defaults.json
          export QSG_USER_FILE=${lib.escapeShellArg cfg.userFile}
          export QSG_BACKDROP_DIR=${lib.escapeShellArg cfg.backdropDir}
          export QSG_PRECEDENCE=${lib.escapeShellArg cfg.precedence}
          export QSG_LOG_LEVEL=${toString cfg.logging.level}
          export QSG_LOG_ARGS=${lib.escapeShellArg logArgs}
          export QSG_LOG_DIR=${lib.escapeShellArg cfg.logging.dir}
          export QSG_LOG_KEEP=${toString cfg.logging.keep}
          export QSG_JOURNAL=${bool01 cfg.logging.journal}
          export QSG_SHOW_LOG=${bool01 cfg.logging.showOnFallback}
          export QSG_THRESHOLD=${toString cfg.crashLoop.threshold}
          export QSG_WINDOW=${toString cfg.crashLoop.window}
          export QSG_FILTER=${lib.escapeShellArg cfg.sessions.filter}
          export QSG_EXTRA_JSON=${lib.escapeShellArg (builtins.toJSON cfg.sessions.extra)}
          export QSG_SHELLS_JSON=${lib.escapeShellArg (builtins.toJSON shellSessions)}
          export QSG_BACKOFF_ENABLE=${bool01 cfg.auth.backoff.enable}
          export QSG_BACKOFF_PERUSER=${bool01 cfg.auth.backoff.perUser}
          export QSG_BACKOFF_FREE=${toString cfg.auth.backoff.free}
          export QSG_BACKOFF_START=${toString cfg.auth.backoff.start}
          export QSG_BACKOFF_MAX=${toString cfg.auth.backoff.max}
          export QSG_IDLE_TIMEOUT=${toString cfg.auth.idleTimeout}
          export QSG_PARSE=${lib.getExe cfg.package.sessionsParse}
          exec qs-greeter-run
        '';
      };
  };
}
