# Thanatos-only gaming layer. Imported by ./amd.nix. Nothing here touches the
# shared nyx/configuration.nix (nyx + aphrodite are unaffected).
# See docs/superpowers/specs/2026-07-14-thanatos-gog-gaming-design.md.
{
  inputs,
  lib,
  pkgs,
  ...
}: let
  # nix-gaming wine builds (real, cached). wine-ge is the default system wine;
  # wine-osu is exposed as a separate `wine-osu` command to switch to for osu!.
  ng = inputs.nix-gaming.packages.${pkgs.system};
  # game-tdp reconciler: validated at build time (shellcheck + unit tests),
  # then PATH-wrapped. Mirrors amd.nix's ryzen-smu-bridge build-time-check idiom.
  gameTdp =
    pkgs.runCommand "game-tdp" {
      nativeBuildInputs = [pkgs.shellcheck pkgs.makeWrapper pkgs.bash];
    } ''
      cp ${./game-tdp/game-tdp.sh} game-tdp.sh
      cp ${./game-tdp/test_game-tdp.sh} test_game-tdp.sh
      shellcheck game-tdp.sh test_game-tdp.sh
      bash test_game-tdp.sh ./game-tdp.sh
      install -Dm755 game-tdp.sh "$out/bin/game-tdp"
      wrapProgram "$out/bin/game-tdp" --prefix PATH : ${lib.makeBinPath [
        pkgs.bash # game-tdp.sh is `#!/usr/bin/env bash`; the systemd service PATH
        # has no bash, so env must find it here or ExecStart exits 127
        pkgs.ryzenadj
        pkgs.inotify-tools
        pkgs.coreutils
        pkgs.gawk
        pkgs.util-linux
        pkgs.systemd
      ]}
    '';

  # gamescope + FSR upscaling convenience wrapper: game-fsr -- <command> [args].
  # Render/output resolutions overridable via env (GAME_FSR_RENDER / _OUTPUT).
  gameFsr = pkgs.writeShellApplication {
    name = "game-fsr";
    runtimeInputs = [pkgs.gamescope];
    text = ''
      render="''${GAME_FSR_RENDER:-1600x900}"
      output="''${GAME_FSR_OUTPUT:-1920x1080}"
      rw="''${render%x*}"
      rh="''${render#*x}"
      ow="''${output%x*}"
      oh="''${output#*x}"
      if [ "''${1:-}" = "--" ]; then shift; fi
      exec gamescope -W "$ow" -H "$oh" -w "$rw" -h "$rh" -F fsr -- "$@"
    '';
  };

  # Manual boost override (mirrors the fan-mode helper). Forces game-tdp's
  # decision independent of gamemode by writing /run/gamemode/override -- the dir
  # game-tdp already watches, so it reacts within a poll (instantly on the write).
  # `on` forces boost (still AC-gated -- never boosts on battery), `off` suppresses
  # it, `auto` returns to gamemode-driven behavior. Clears on reboot (/run tmpfs).
  gameBoost = pkgs.writeShellApplication {
    name = "game-boost";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      mode="''${1:-}"
      dir=/run/gamemode
      [ -d "$dir" ] || { echo "game-boost: game-tdp not running (no $dir)" >&2; exit 1; }
      case "$mode" in
        on | off) printf '%s\n' "$mode" >"$dir/override" ;;
        auto) : >"$dir/override" ;;
        *) echo "usage: game-boost on|off|auto" >&2; exit 2 ;;
      esac
      echo "game-boost: $mode (boost still requires AC; clears on reboot)"
    '';
  };
in {
  # ---- GOG / Windows-game launch + overlay layer -------------------------
  environment.systemPackages = [
    pkgs.umu-launcher # Steam Linux Runtime; Heroic auto-detects; umu CLI path
    pkgs.mangohud # 64-bit overlay + `mangohud <cmd>` + MANGOHUD=1 layer
    pkgs.pkgsi686Linux.mangohud # 32-bit Vulkan layer for 32-bit Proton games
    pkgs.minigalaxy # native GOG client (DRM-free installs)
    pkgs.lgogdownloader # CLI to download/archive DRM-free GOG installers
    gameFsr
    gameBoost # manual `game-boost on|off|auto` TDP override (independent of gamemode)

    # Wine: wine-ge is the default `wine` (provides wine/wine64/wineserver/...).
    # wine-osu ships its own bin/wine and would collide, so it is exposed as a
    # separate `wine-osu` command to switch to when needed (e.g. for osu!).
    ng.wine-ge
    (pkgs.writeShellScriptBin "wine-osu" ''
      exec ${ng.wine-osu}/bin/wine "$@"
    '')
  ];

  # Proton-GE for Steam AND Heroic (reads Steam's compatibilitytools.d).
  # programs.steam.enable lives in the shared nyx config; this only appends to
  # the list (module merge). proton-ge-bin is the nixpkgs package that conforms
  # to extraCompatPackages -- nix-gaming's proton-ge was deprecated 2024-03-17 in
  # its favor; it is a prebuilt binary from the nixpkgs cache, not a source build.
  programs.steam.extraCompatPackages = [
    pkgs.proton-ge-bin
  ];

  # ---- Simple tunables (thanatos-only) -----------------------------------
  # SteamOS value; prevents crashes/stutter in many DX12/Proton titles.
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;
  # Separate list; NixOS concatenates with amd.nix's own boot.kernelParams.
  boot.kernelParams = ["amd_pstate=active" "split_lock_detect=off"];
  # Shared nyx config sets this false; mkForce keeps the override thanatos-only.
  services.pipewire.lowLatency.enable = lib.mkForce true;

  # ---- APU TDP boost: root reconciler + gamemode hooks -------------------
  # Marker dir owned by the gaming user so gamemode's user-level custom hooks can
  # create/remove /run/gamemode/active. The marker is ONLY a fast wake trigger;
  # game-tdp decides boost from live gamemode ClientCount + AC, not the marker.
  systemd.tmpfiles.rules = ["d /run/gamemode 0755 michael users -"];

  systemd.services.game-tdp = {
    description = "APU TDP boost while a gamemode client is active (AC only)";
    wantedBy = ["multi-user.target"];
    after = ["ryzen-smu-bridge.service"];
    wants = ["ryzen-smu-bridge.service"];
    serviceConfig = {
      ExecStart = "${gameTdp}/bin/game-tdp run";
      # Cleanup: reverting on ANY stop of THIS unit never leaves the CPU boosted.
      ExecStopPost = "${gameTdp}/bin/game-tdp revert";
      Restart = "always";
      RestartSec = 5;
      LogLevelMax = "info";
    };
  };

  # gamemode: GPU perf level (applied by gamemode's own helper, reverted on exit)
  # + marker hooks (fast wake only). programs.gamemode.enable/enableRenice live in
  # the shared nyx config; setting .settings here merges with them.
  programs.gamemode.settings = {
    gpu = {
      apply_gpu_optimisations = "accept-responsibility";
      gpu_device = 0;
      amd_performance_level = "high";
    };
    custom = {
      start = "${pkgs.coreutils}/bin/touch /run/gamemode/active";
      end = "${pkgs.coreutils}/bin/rm -f /run/gamemode/active";
    };
  };

  # Instant reaction to AC changes (correctness already guaranteed by the daemon's
  # <=POLL-second poll; this just makes the revert instant). Poking any file in
  # /run/gamemode wakes the daemon's inotify watch, which re-reads AC + clients.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ACTION=="change", RUN+="${pkgs.coreutils}/bin/touch /run/gamemode/.ac"
  '';
}
