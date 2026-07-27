// features/hm/wayland/quickshell/task-bar/lock/LockConfig.qml
pragma Singleton
import Quickshell
import Quickshell.Io

// Reads the Nix-written lock config kept OUTSIDE the ~/.config/quickshell repo
// symlink (same seam shape as quickshell-idle/policy.json). Defaults are safe if
// the file is absent.
Singleton {
    id: root

    property bool failOpenOnCrash: true
    property string fallbackImage: (Quickshell.env("HOME") || "") + "/.local/share/lockscreen.png"

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
            } catch (e) {
                // keep defaults
            }
        }
    }
}
