pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Tracks the active Hyprland submap (compositor-wide) plus the key-hint data for
// each submap. Instantiated once at ShellRoot level and passed by reference to
// each Taskbar (like BluetoothService/AudioService). `current` is "" in the
// default map. Hints come from ~/.config/quickshell-modes/hints.json, emitted by
// hyprland.nix (the same submapHints attrset that feeds the Super+/ cheatsheet).
QtObject {
    id: root

    property string current: ""
    property var hints: ({})

    readonly property var meta: root.hints[root.current] || null
    function label() {
        return root.meta ? root.meta.label : root.current.toUpperCase();
    }
    function iconCp() {
        return (root.meta && root.meta.icon) ? root.meta.icon : "";
    }
    function keys() {
        return (root.meta && root.meta.keys) ? root.meta.keys : [];
    }

    property Connections hyprConn: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap")
                root.current = event.data;
        }
    }

    property FileView file: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell-modes/hints.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.hints = JSON.parse(file.text());
            } catch (e) {
                root.hints = {};
            }
        }
        onLoadFailed: root.hints = {}
        Component.onCompleted: reload()
    }
}
