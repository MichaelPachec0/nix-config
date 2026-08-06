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

    screen: modelData
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
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
        }
        Text {
            color: "#d0d0d0"
            font.pixelSize: 15
            text: root.reason
        }
        Text {
            color: "#d0d0d0"
            font.pixelSize: 15
            text: "Press Ctrl+Alt+F" + (Quickshell.env("QSG_TTY_HINT") || "2")
                + " for a text login."
        }
    }
}
