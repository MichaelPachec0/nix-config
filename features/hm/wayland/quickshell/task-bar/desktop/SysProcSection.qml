import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib/sysfmt.js" as SysFmt

// Process section: two-column Top-memory / Top-CPU lists with interactive kill.
// Single click arms the row (3 s timeout); second click sends SIGTERM.
// Shift+click sends SIGKILL immediately. Middle-click copies "pid name" via wl-copy.
ColumnLayout {
    id: root
    spacing: 4

    required property QtObject theme
    required property var stats

    function sevColor(sev) {
        return sev === "good" ? theme.accentGreen
             : sev === "fair" ? theme.accentYellow : theme.accentRed;
    }

    // Two-column layout: Top memory | Top CPU
    RowLayout {
        Layout.fillWidth: true
        spacing: 16

        // Top memory column
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 2

            Text {
                text: "Top memory"
                font.family: root.theme.iconFont; font.pixelSize: 11; font.weight: Font.DemiBold
                color: root.theme.textSecondary
            }

            Repeater {
                model: root.stats.topMem
                delegate: Item {
                    id: memDelegate
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: memRow.implicitHeight

                    property bool armed: false

                    Timer {
                        id: memDisarm
                        interval: 3000
                        onTriggered: memDelegate.armed = false
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: memArea.containsMouse ? root.theme.bgItemHover : "transparent"
                        radius: 2
                    }

                    RowLayout {
                        id: memRow
                        anchors { left: parent.left; right: parent.right }
                        Text {
                            text: modelData.name
                            font.family: root.theme.iconFont; font.pixelSize: 10
                            color: root.theme.textPrimary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: memDelegate.armed ? "end?" : SysFmt.fmtKB(modelData.rssKB)
                            font.family: root.theme.iconFont; font.pixelSize: 10
                            color: memDelegate.armed ? root.theme.accentRed : root.theme.textSecondary
                        }
                    }

                    MouseArea {
                        id: memArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: function (m) {
                            if (m.button === Qt.MiddleButton) {
                                Quickshell.execDetached(["bash", "-lc",
                                    "printf '%s' \"$1\" | wl-copy", "_",
                                    modelData.pid + " " + modelData.name]);
                                return;
                            }
                            if (m.modifiers & Qt.ShiftModifier) {
                                Quickshell.execDetached(["kill", "-KILL", String(modelData.pid)]);
                                return;
                            }
                            if (!memDelegate.armed) {
                                memDelegate.armed = true;
                                memDisarm.restart();
                            } else {
                                Quickshell.execDetached(["kill", "-TERM", String(modelData.pid)]);
                                memDelegate.armed = false;
                            }
                        }
                    }
                }
            }
        }

        // Top CPU column
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 2

            Text {
                text: "Top CPU"
                font.family: root.theme.iconFont; font.pixelSize: 11; font.weight: Font.DemiBold
                color: root.theme.textSecondary
            }

            Repeater {
                model: root.stats.topCpu
                delegate: Item {
                    id: cpuDelegate
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: cpuRow.implicitHeight

                    property bool armed: false

                    Timer {
                        id: cpuDisarm
                        interval: 3000
                        onTriggered: cpuDelegate.armed = false
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: cpuArea.containsMouse ? root.theme.bgItemHover : "transparent"
                        radius: 2
                    }

                    RowLayout {
                        id: cpuRow
                        anchors { left: parent.left; right: parent.right }
                        Text {
                            text: modelData.name
                            font.family: root.theme.iconFont; font.pixelSize: 10
                            color: root.theme.textPrimary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: cpuDelegate.armed ? "end?" : (modelData.pcpu + "%")
                            font.family: root.theme.iconFont; font.pixelSize: 10
                            color: cpuDelegate.armed ? root.theme.accentRed : root.theme.textSecondary
                        }
                    }

                    MouseArea {
                        id: cpuArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: function (m) {
                            if (m.button === Qt.MiddleButton) {
                                Quickshell.execDetached(["bash", "-lc",
                                    "printf '%s' \"$1\" | wl-copy", "_",
                                    modelData.pid + " " + modelData.name]);
                                return;
                            }
                            if (m.modifiers & Qt.ShiftModifier) {
                                Quickshell.execDetached(["kill", "-KILL", String(modelData.pid)]);
                                return;
                            }
                            if (!cpuDelegate.armed) {
                                cpuDelegate.armed = true;
                                cpuDisarm.restart();
                            } else {
                                Quickshell.execDetached(["kill", "-TERM", String(modelData.pid)]);
                                cpuDelegate.armed = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
