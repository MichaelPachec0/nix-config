# ff-hyprland-bridge: Firefox <-> Hyprland bridge (pkgs/ff-hyprland-bridge).
# Two jobs, one extension, one native host, one config file:
#   video: reports playing <video> rects so hyprglass can undim them
#          (hyprglass_rect: tags, no_dim, hyprglass_disabled).
#   hdr:   answers video-dynamic-range per Firefox window from the EDID of the
#          monitor the window is on. Firefox's content process cannot do this
#          on Wayland (no window position; every window resolves to the first
#          wl_output), so YouTube would only offer HDR with
#          gfx.color_management.hdr.force_enabled, on every screen.
# The host reads the config file and hands the extension its half over the
# native-messaging port, so this module is the single source for both.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ffHyprlandBridge;
  bridgePkg = pkgs.callPackage ../../../pkgs/ff-hyprland-bridge {};
in {
  options.ffHyprlandBridge = {
    enable = lib.mkEnableOption "the Firefox to Hyprland bridge (native host + unpacked extension)";

    video = {
      playbackAction = lib.mkOption {
        type = lib.types.enum ["strip" "undim" "rect"];
        default = "rect";
        description = ''
          While video plays: strip = hyprglass_disabled + no_blur + no_dim on
          the whole window; undim = no_dim only; rect = undim ONLY the
          on-screen video rect(s), which the extension reports as
          hyprglass_rect: tags and the plugin's dim overlay honours.
        '';
      };
      rectFallback = lib.mkOption {
        type = lib.types.enum ["none" "undim" "strip"];
        default = "none";
        description = ''
          rect mode only: what to do when the window reports playback but no
          visible rect (video scrolled out, hidden tab, canvas players, PiP).
          none keeps Hyprland's normal dim.
        '';
      };
      rectRateHz = lib.mkOption {
        type = lib.types.ints.between 1 60;
        default = 10;
        description = ''
          rect mode only: cap on rect updates per window per second while the
          rect moves (scroll/resize). Each update costs one hyprctl fork and
          one window-rule re-evaluation in the compositor.
        '';
      };
      playSignal = lib.mkOption {
        type = lib.types.enum ["activeTab" "audible" "any"];
        default = "activeTab";
        description = "Which playing videos count: the window's visible tab only, unmuted ones anywhere, or any at all.";
      };
      pauseGraceMs = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3000;
        description = "Pause must survive this long before tags clear, so seeks do not strobe the glass.";
      };
    };

    extension = {
      install = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Link the unsigned XPI into the profile's extensions/ dir so the
          extension persists across Firefox restarts. A temporary add-on
          loaded via about:debugging dies with the browser, which twice
          left every window untagged after a switch. Needs
          xpinstall.signatures.required=false and
          extensions.autoDisableScopes=0 in the profile's user.js
          (Developer Edition honours the first); Firefox picks the file up
          at its next start.
        '';
      };
      profileDir = lib.mkOption {
        type = lib.types.str;
        default = config.hyprglass.firefox.profileDir;
        description = "Profile directory name under ~/.mozilla/firefox that receives the XPI.";
      };
    };

    hdr.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Answer (video-)dynamic-range per window from the monitor's EDID. Off
        = the hook stays inert and Firefox's own (first-output) answer stands.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # One config file for the whole bridge; the host reads it and hands the
    # extension its half (playSignal, pauseGraceMs, rectRateHz, hdr) over the
    # port.
    xdg.configFile."ff-hyprland-bridge.json".text = builtins.toJSON {
      inherit (cfg.video) playbackAction playSignal pauseGraceMs rectFallback rectRateHz;
      hdrEnable = cfg.hdr.enable;
    };

    # Links lib/mozilla/native-messaging-hosts/*.json into firefox's search
    # path; the extension itself is loaded unpacked from
    # ${bridgePkg}/share/ff-hyprland-bridge/extension via about:debugging.
    programs.firefox.nativeMessagingHosts = [bridgePkg];

    # Same layout home-manager's profiles.<p>.extensions.packages produces,
    # but by hand: this profile is not HM-declared (declaring it would make HM
    # own profiles.ini), so only the one file is linked.
    home.file.".mozilla/firefox/${cfg.extension.profileDir}/extensions/${bridgePkg.extensionId}.xpi" =
      lib.mkIf cfg.extension.install {
        source = "${bridgePkg}/share/ff-hyprland-bridge/${bridgePkg.extensionId}.xpi";
      };
  };
}
