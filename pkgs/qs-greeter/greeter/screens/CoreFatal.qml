import QtQuick
import Quickshell
import Quickshell.Wayland

// Last rung of the skin fallback chain, wired in by shell.qml as a sibling
// of the login window. Deliberately built from plain QML types only -- no
// widget kit, no palette, no font beyond the default -- so that whatever
// broke the skin cannot break this screen as well.
PanelWindow {
    id: root
    required property var modelData
    required property string reason
    // Defaults true for the (currently hypothetical) single-instance
    // caller; shell.qml's own Variants-driven instantiation passes this
    // explicitly per output so only one of possibly several simultaneous
    // instances ever claims WlrKeyboardFocus.Exclusive -- see shell.qml's
    // isPrimaryScreen() for why granting Exclusive to more than one
    // layer-shell surface at once is avoided rather than relied on.
    property bool keyboardExclusive: true

    screen: modelData
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.keyboardExclusive
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "qs-greeter:fatal"
    anchors { top: true; bottom: true; left: true; right: true }
    color: "#101010"

    Column {
        anchors.centerIn: parent
        spacing: 12
        Text {
            color: "#ffffff"
            font.pixelSize: 22
            text: "The greeter could not start."
            textFormat: Text.PlainText
        }
        Text {
            color: "#d0d0d0"
            font.pixelSize: 15
            text: root.reason
            textFormat: Text.PlainText
        }
        Text {
            color: "#d0d0d0"
            font.pixelSize: 15
            text: "Press Ctrl+Alt+F" + (Quickshell.env("QSG_TTY_HINT") || "2")
                + " for a text login."
            textFormat: Text.PlainText
        }
    }
}
