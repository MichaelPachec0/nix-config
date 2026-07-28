// features/hm/wayland/quickshell/task-bar/lock/LockConfig.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Reads the Nix-written lock config kept OUTSIDE the ~/.config/quickshell repo
// symlink (same seam shape as quickshell-idle/policy.json). Defaults are safe if
// the file is absent.
Singleton {
    id: root

    property bool failOpenOnCrash: true
    property string fallbackImage: (Quickshell.env("HOME") || "") + "/.local/share/lockscreen.png"

    // activate-linux watermark params, mirrored from the SAME
    // quickshellLock.watermark Nix option that builds the real activate-linux
    // CLI invocation (hyprland.nix/sway.nix) -- keeps the lock's under-lock
    // replica (LockSurface.qml) in sync with the desktop overlay. Defaults
    // here match the option's Nix defaults, for correctness before an HM
    // switch has ever written config.json.
    property bool watermarkEnable: true
    property string watermarkTitle: "Activate NixOS"
    property string watermarkMessage: "Edit configuration.nix to activate NixOS."
    property color watermarkColor: Qt.rgba(1, 1, 1, 0.10)
    property int watermarkWidth: 360
    property int watermarkHeight: 120

    function _parseWmColor(s) {
        var p = (s || "").split("-");
        return (p.length === 4)
            ? Qt.rgba(parseFloat(p[0]), parseFloat(p[1]), parseFloat(p[2]), parseFloat(p[3]))
            : Qt.rgba(1, 1, 1, 0.10);
    }

    readonly property string _path: (Quickshell.env("HOME") || "") + "/.config/quickshell-lock/config.json"

    FileView {
        id: file
        path: root._path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var o = JSON.parse(file.text());
                if (o.failOpenOnCrash !== undefined) root.failOpenOnCrash = !!o.failOpenOnCrash;
                if (o.fallbackImage) root.fallbackImage = o.fallbackImage;
                if (o.watermark) {
                    var w = o.watermark;
                    if (w.enable !== undefined) root.watermarkEnable = !!w.enable;
                    if (w.title !== undefined) root.watermarkTitle = w.title;
                    if (w.message !== undefined) root.watermarkMessage = w.message;
                    if (w.color) root.watermarkColor = root._parseWmColor(w.color);
                    if (w.width) root.watermarkWidth = w.width;
                    if (w.height) root.watermarkHeight = w.height;
                }
            } catch (e) {
                // keep defaults
            }
        }
    }
}
