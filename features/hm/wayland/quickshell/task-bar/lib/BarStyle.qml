pragma Singleton
import Quickshell
import Quickshell.Io

// Live bar look ("ghost" | "frosted"), toggled by the `bar-style` command via a
// state file kept OUTSIDE the ~/.config/quickshell repo symlink so it never
// dirties the repo. watchChanges -> hot-swaps with no reload. Defaults to
// "frosted" when the file is absent/invalid. A singleton so Pill and BarText
// read it without threading `theme` (or a style prop) to every glyph.
Singleton {
    id: root

    property string current: "frosted"

    readonly property string _stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"

    FileView {
        id: file
        path: root._stateDir + "/bar-style"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var t = (file.text() || "").trim();
            root.current = (t === "ghost" || t === "ghost-glass") ? t : "frosted";
        }
    }
}
