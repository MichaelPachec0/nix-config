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
  };
}
