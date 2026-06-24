import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

ShellRoot {
    PanelWindow {
        id: bar

        anchors {
            top: true
            left: true
            right: true
        }
        implicitHeight: 56
        color: "#ee1d2021"

        // Qualified via `bar.` below: a bare `activeWs` is not resolvable from
        // inside Repeater delegates (only document-root props + ids are).
        readonly property int activeWs: Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10

            // (1) Workspaces -- enumerate + highlight active
            Repeater {
                model: Hyprland.workspaces
                Rectangle {
                    required property var modelData
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 8
                    color: modelData.id === bar.activeWs ? "#87b158" : "#3c3836"
                    Text {
                        anchors.centerIn: parent
                        text: modelData.id
                        color: modelData.id === bar.activeWs ? "#1d2021" : "#ebdbb2"
                    }
                    MouseArea {
                        anchors.fill: parent
                        // Lua dispatch (configType="lua"): switch workspace.
                        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + modelData.id + " })")
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: "#504945"
            }

            // (2) Windows on the active workspace + (3) click-to-focus
            Repeater {
                model: Hyprland.toplevels
                Rectangle {
                    required property var modelData
                    readonly property bool onActive: (modelData.workspace?.id ?? -2) === bar.activeWs
                    readonly property bool isActive: modelData === Hyprland.activeToplevel
                    readonly property string addr: {
                        // Quickshell's .address is bare hex (no 0x); Hyprland's
                        // "address:" selector requires the 0x prefix. Normalize.
                        var a = (modelData.address && modelData.address.length > 0) ? modelData.address : (modelData.lastIpcObject?.address ?? "")
                        return (a.indexOf("0x") === 0) ? a : ("0x" + a)
                    }
                    visible: onActive
                    implicitWidth: lbl.implicitWidth + 18
                    implicitHeight: 30
                    radius: 8
                    color: isActive ? "#87b158" : "#2d353b"
                    Text {
                        id: lbl
                        anchors.centerIn: parent
                        text: (modelData.lastIpcObject?.class ?? modelData.title ?? "?") + " [" + addr.slice(-4) + "]"
                        color: isActive ? "#1d2021" : "#ebdbb2"
                    }
                    MouseArea {
                        anchors.fill: parent
                        // Lua dispatch: focus window by address (layout-agnostic;
                        // raises a tabbed-hidden window under hy3).
                        onClicked: Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
