pragma Singleton
import QtQuick // for the Component attached object on FileView below
import Quickshell
import Quickshell.Io

// Disk-persisted media UI state, currently just the marquee policy.
//
// A singleton rather than a CalState-style instance because both ends of this
// setting are far apart in the tree: the bar's MediaWidget reads it to gate its
// scroll timer, and MediaPopup writes it from a chip. Threading a property
// through Taskbar -> MediaWidget -> MediaPopup for one bool is not worth it, and
// the lib/ singleton pattern (see BarStyle, read bare by Pill and BarText) is
// already the house answer to exactly that. Same FileView idiom as CalState,
// including the one-shot mkdir -p, because FileView does not create parent dirs.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/state/quickshell"

    // false = scroll only while the widget is hovered (default), true = scroll
    // continuously whenever the text overflows and something is playing.
    //
    // Defaults to hover-only because the always-on behaviour is a measurable
    // battery cost, not a cosmetic preference: a 10-minute idle window with the
    // marquee running measured quickshell at 6.68% CPU and Hyprland at 3.65%
    // sustained -- the bar layer is blurred, so every marquee frame also makes
    // the compositor re-run its blur passes -- against 9.12 W total draw. That
    // is more than every scheduler and runtime-PM tuning on this machine put
    // together. Opt back in per-taste via the popup; it is a real trade, not a
    // free one.
    property alias marqueeAlways: adapter.marqueeAlways

    Process {
        running: true
        command: ["mkdir", "-p", root.dir]
    }

    FileView {
        id: file
        path: root.dir + "/media-ui.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        Component.onCompleted: reload()

        JsonAdapter {
            id: adapter
            property bool marqueeAlways: false
        }
    }
}
