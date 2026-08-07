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

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/qs-greeter";
      description = ''
        Persistent (non-tmpfs) parent directory for the writable settings
        tier and the greeter-written last-user/last-session state. The
        single source for the tmpfiles rule that creates it: userFile and
        stateFile both default to paths under this directory, so pointing
        either of them somewhere else no longer silently leaves tmpfiles
        creating the wrong parent (or none at all). Distinct from stateDir
        below, which is deliberately tmpfs-backed.
      '';
    };

    userFile = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dataDir}/settings.json";
      description = "Group-writable cosmetic settings file.";
    };

    stateFile = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dataDir}/state.json";
      description = ''
        Where GreeterState.qml persists the last-logged-in username and
        session across boots (QSG_STATE_FILE). Written by the unprivileged
        greeter user itself, so it needs no tmpfiles `f` rule of its own --
        only dataDir's own directory has to exist first.
      '';
    };

    primaryOutput = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Connector name (e.g. "eDP-1") of the one output whose login window
        may hold exclusive keyboard focus (QSG_PRIMARY_OUTPUT). shell.qml
        renders the login dialog on every connected output regardless of
        this setting; it only decides which single output's window actually
        receives keystrokes, because a layer-shell surface's "exclusive"
        keyboard mode locks out every other surface, and only one may ever
        safely claim it. null falls back to whichever output Quickshell
        lists first -- fine on a single-monitor machine, and the same choice
        this greeter always made before this option existed. Set it
        explicitly on any host where a closed-lid or otherwise unreachable
        output could sort first (a docked laptop being the concrete case
        that motivated this option). If the named output is not currently
        connected (e.g. the same laptop undocked), shell.qml falls back to
        the same "whichever output Quickshell lists first" behavior rather
        than leaving no output holding the keyboard at all.
      '';
    };

    sessionEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {WLR_DRM_NO_MODIFIERS = "1";};
      description = ''
        Environment variables merged into every launched session
        (QSG_SESSION_ENV), applied underneath -- and overridable by -- each
        session entry's own `env`. Defaults to the same
        WLR_DRM_NO_MODIFIERS=1 programs.regreet.settings.env carries, for
        parity with the backend this module replaces.
      '';
    };

    backdropDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/qs-greeter/backdrops";
      description = "Only directory the greeter will load backdrop images from.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/qs-greeter";
      description = ''
        Where the wrapper keeps its crash-loop counter and writes the
        generated sessions.json that the greeter reads. Deliberately
        tmpfs-backed (/run by default): the crash counter must survive
        greetd restarting the compositor within one boot (that is the loop
        being caught) but reset on reboot, since a reboot is a deliberate
        retry. This is the single source for both QSG_STATE_DIR (read by
        the wrapper) and QSG_SESSIONS (read by the greeter, derived as
        stateDir + "/sessions.json") -- they used to be two independently
        hardcoded literals that only agreed by coincidence.
      '';
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
      "d ${cfg.dataDir} 0755 greeter ${cfg.group} - -"
      "d ${cfg.backdropDir} 0775 greeter ${cfg.group} - -"
      "d ${cfg.logging.dir} 0750 greeter greeter - -"
      "f ${cfg.userFile} 0664 greeter ${cfg.group} - -"
      # State dir for the wrapper's crash counter and generated
      # sessions.json -- see cfg.stateDir for why it's tmpfs-backed. /run is
      # root:root 0755, so without this the wrapper's own
      # `mkdir -p "$state_dir"`, run as the unprivileged greeter user, would
      # fail on every boot.
      "d ${cfg.stateDir} 0750 greeter greeter - -"
    ];

    environment.systemPackages = [cfg.package];

    # wine-fonts, not corefonts: corefonts ships Tahoma regular only, while
    # wine-fonts carries tahoma.ttf, tahomabd.ttf (XP uses bold for labels)
    # and marlett.ttf, whose glyphs are the combo arrow and window marks --
    # vector, so they stay crisp at any DPI with no bitmap assets. This
    # nixpkgs pin has no top-level `wine-fonts` attribute (only wine's own
    # font derivation, exposed as `winePackages.fonts` / `wine64Packages.fonts`
    # / `wineWow64Packages.fonts` -- all three are the same package, since
    # fonts.nix does not depend on which wine build called it); confirmed by
    # building it and finding tahoma.ttf, tahomabd.ttf and marlett.ttf under
    # its share/fonts/truetype/.
    fonts.packages = [pkgs.winePackages.fonts];

    # Cosmetic defaults, rendered from the Nix tier. Valid by construction --
    # it comes from toJSON, not from a parser -- which is why the merge code
    # can treat it as trusted and fall back to it unconditionally.
    environment.etc."qs-greeter/defaults.json".text = builtins.toJSON {
      skin = cfg.skin;
      # The palette allow-list SettingsMerge.js actually enforces at
      # runtime -- see Skin.qml's `_palettes` name-to-instance map and
      # skins/xp/meta.json's own (decorative, read by nothing) `palettes`
      # field for the other two places this same list is written down.
      # All three must move together; nothing enforces that automatically.
      skins = {xp = {palettes = ["luna" "gruvbox"];};};
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
    # QSG_* variable the QML (Settings.qml/Log.qml/Session.qml/Sessions.qml/
    # GreeterState.qml) or the wrapper script itself reads is set here from
    # the matching Nix option -- an unset QSG_* would silently fall back to
    # its hardcoded default in the script, which is a default nobody using
    # this module actually chose. QSG_SESSIONS_DIR and QSG_TTY_HINT are
    # deliberately left unset: neither has a matching Nix option (session
    # dir is the real wayland-sessions dir; the TTY hint is plumbing shared
    # verbatim between this script and CoreFatal.qml's own hardcoded
    # default), so there is nothing here to override. QSG_STATE_DIR and
    # QSG_SESSIONS both come from cfg.stateDir below -- one option, one
    # source, so the wrapper (which writes sessions.json under
    # QSG_STATE_DIR) and the greeter (which reads it from QSG_SESSIONS) can
    # never independently drift onto different paths. QSG_STATE_FILE
    # (GreeterState.qml's persisted last-user/last-session) similarly comes
    # from cfg.stateFile, itself derived from cfg.dataDir alongside
    # QSG_USER_FILE -- see dataDir's own description for why both being
    # derived from the same option is what actually keeps the tmpfiles rule
    # honest.
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
          export QSG_STATE_FILE=${lib.escapeShellArg cfg.stateFile}
          export QSG_BACKDROP_DIR=${lib.escapeShellArg cfg.backdropDir}
          export QSG_STATE_DIR=${lib.escapeShellArg cfg.stateDir}
          export QSG_SESSIONS=${lib.escapeShellArg "${cfg.stateDir}/sessions.json"}
          export QSG_PRIMARY_OUTPUT=${lib.escapeShellArg (
            if cfg.primaryOutput == null then "" else cfg.primaryOutput
          )}
          export QSG_SESSION_ENV=${lib.escapeShellArg (builtins.toJSON cfg.sessionEnv)}
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
