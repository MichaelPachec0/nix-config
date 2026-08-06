import QtQuick
import Quickshell
import Quickshell.Wayland

// Last rung of the skin fallback chain. Deliberately uses no widget, no
// palette, and no font beyond the default: it must be unbreakable by whatever
// broke the skin. Not yet wired into shell.qml -- the fallback chain that
// selects this screen is built in a later task alongside the skin loader.
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
