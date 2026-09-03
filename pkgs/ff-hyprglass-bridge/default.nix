# ff-hyprglass-bridge: WebExtension + native-messaging host pair that tells
# Hyprland (hyprglass) when a Firefox window is playing video.
#
# The host package carries lib/mozilla/native-messaging-hosts/<name>.json,
# which is exactly the layout programs.firefox.nativeMessagingHosts links
# into the browser's search path. The extension ships as an unpacked
# directory ($out/share/ff-hyprglass-bridge/extension) loaded temporarily
# via about:debugging for v1; signing is a recorded follow-up.
{
  lib,
  python3,
  runCommand,
}: let
  hostName = "ff_hyprglass_bridge";
  extensionId = "ff-hyprglass-bridge@michaelpacheco.org";
in
  runCommand "ff-hyprglass-bridge" {
    nativeBuildInputs = [python3];
    meta = {
      description = "Firefox to Hyprland video-playback bridge for hyprglass";
      license = lib.licenses.bsd3;
      platforms = lib.platforms.linux;
    };
  } ''
    mkdir -p $out/bin $out/lib/mozilla/native-messaging-hosts $out/share/ff-hyprglass-bridge

    # host
    install -m0755 ${./host/ff_hyprglass_bridge.py} $out/bin/${hostName}
    patchShebangs $out/bin/${hostName}
    python3 -m py_compile $out/bin/${hostName}

    # native-messaging manifest; hyprctl is resolved from the session PATH on
    # purpose -- the running compositor's hyprctl must match the compositor,
    # not whatever this package pinned at build time.
    cat > $out/lib/mozilla/native-messaging-hosts/${hostName}.json <<MANIFEST
    {
      "name": "${hostName}",
      "description": "hyprglass video-playback bridge",
      "path": "$out/bin/${hostName}",
      "type": "stdio",
      "allowed_extensions": ["${extensionId}"]
    }
    MANIFEST
    python3 -c "import json; json.load(open('$out/lib/mozilla/native-messaging-hosts/${hostName}.json'))"

    # unpacked extension
    cp -r ${./extension} $out/share/ff-hyprglass-bridge/extension
  ''
