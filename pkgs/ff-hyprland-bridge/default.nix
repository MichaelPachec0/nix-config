# ff-hyprland-bridge: WebExtension + native-messaging host pair between
# Firefox and Hyprland. Two jobs: (1) report video playback rects so hyprglass
# can undim them; (2) answer video-dynamic-range per window from the monitor's
# EDID, which Firefox's content process cannot do on Wayland (it has no window
# position and resolves every window to the first wl_output).
#
# The host package carries lib/mozilla/native-messaging-hosts/<name>.json,
# which is exactly the layout programs.firefox.nativeMessagingHosts links
# into the browser's search path. The extension ships twice: unpacked
# ($out/share/ff-hyprland-bridge/extension, for about:debugging) and as an
# unsigned XPI ($out/share/ff-hyprland-bridge/<id>.xpi) that the HM module
# drops into the profile's extensions/ dir, so it survives Firefox restarts
# (a temporary add-on does not). Developer Edition loads it with
# xpinstall.signatures.required=false; AMO signing is a recorded follow-up.
{
  lib,
  python3,
  runCommand,
  zip,
}: let
  hostName = "ff_hyprland_bridge";
  extensionId = "ff-hyprland-bridge@michaelpacheco.org";
in
  runCommand "ff-hyprland-bridge" {
    nativeBuildInputs = [python3 zip];
    passthru.extensionId = extensionId;
    meta = {
      description = "Firefox to Hyprland bridge: video playback rects for hyprglass, per-window HDR capability for pages";
      license = lib.licenses.bsd3;
      platforms = lib.platforms.linux;
    };
  } ''
    mkdir -p $out/bin $out/lib/mozilla/native-messaging-hosts $out/share/ff-hyprland-bridge

    # host
    install -m0755 ${./host/ff_hyprland_bridge.py} $out/bin/${hostName}
    patchShebangs $out/bin/${hostName}
    python3 -m py_compile $out/bin/${hostName}

    # Unit tests for the host's pure parts (EDID parser, mapper, bridge).
    (cd ${./host} && python3 -m unittest discover -s tests -t . -q)

    # native-messaging manifest; hyprctl is resolved from the session PATH on
    # purpose -- the running compositor's hyprctl must match the compositor,
    # not whatever this package pinned at build time.
    cat > $out/lib/mozilla/native-messaging-hosts/${hostName}.json <<MANIFEST
    {
      "name": "${hostName}",
      "description": "Firefox to Hyprland bridge (hyprglass playback rects, per-window HDR)",
      "path": "$out/bin/${hostName}",
      "type": "stdio",
      "allowed_extensions": ["${extensionId}"]
    }
    MANIFEST
    python3 -c "import json; json.load(open('$out/lib/mozilla/native-messaging-hosts/${hostName}.json'))"

    # unpacked extension, plus the same tree zipped as an XPI (-X: no extra
    # attributes, -D: no directory entries, so the archive is reproducible)
    cp -r ${./extension} $out/share/ff-hyprland-bridge/extension
    python3 -c "import json; m=json.load(open('$out/share/ff-hyprland-bridge/extension/manifest.json')); assert m['browser_specific_settings']['gecko']['id']=='${extensionId}'"
    (cd $out/share/ff-hyprland-bridge/extension && zip -q -X -D -r $out/share/ff-hyprland-bridge/${extensionId}.xpi .)
  ''
