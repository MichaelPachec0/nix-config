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

    // Two-click kill arm state lives on the SECTION, keyed by pid, not on the row
    // delegate. The top-N model is reassigned every poll (ps output changes each
    // tick), which recreates the delegates and would reset any per-delegate flag
    // before the confirming second click. Keying by pid survives that churn and
    // retargets to the right process automatically.
    property int armedPid: -1
    property Timer disarmTimer: Timer {
        interval: 3000
        onTriggered: root.armedPid = -1
    }
    function armOrKill(pid) {
        if (root.armedPid !== pid) {
            root.armedPid = pid;
            root.disarmTimer.restart();
        } else {
            Quickshell.execDetached(["kill", "-TERM", String(pid)]);
            root.armedPid = -1;
        }
    }

    function sevColor(sev) {
        return sev === "good" ? theme.accentGreen
             : sev === "fair" ? theme.accentYellow : theme.accentRed;
    }

    // Reserve the numeric column so a process name never gets shoved right by a
    // wider figure and bleeds from the left (memory) column into the right (CPU).
    readonly property real _wMem: _mMem.advanceWidth
    readonly property real _wCpu: _mCpu.advanceWidth
    TextMetrics { id: _mMem; font.family: root.theme.iconFont; font.pixelSize: 10; text: "1023M" }
    TextMetrics { id: _mCpu; font.family: root.theme.iconFont; font.pixelSize: 10; text: "100.0%" }

    // Two-column layout: Top memory | Top CPU
    RowLayout {
        Layout.fillWidth: true
        spacing: 16

        // Top memory column
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 2
            clip: true

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

                    readonly property bool armed: memDelegate.modelData.pid === root.armedPid

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
                            horizontalAlignment: Text.AlignRight
                            Layout.minimumWidth: root._wMem
                            Layout.preferredWidth: root._wMem
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
                                Quickshell.execDetached(["bash", "-c",
                                    "printf '%s' \"$1\" | wl-copy", "_",
                                    modelData.pid + " " + modelData.name]);
                                return;
                            }
                            if (m.modifiers & Qt.ShiftModifier) {
                                Quickshell.execDetached(["kill", "-KILL", String(modelData.pid)]);
                                return;
                            }
                            root.armOrKill(modelData.pid);
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
            clip: true

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

                    readonly property bool armed: cpuDelegate.modelData.pid === root.armedPid

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
                            horizontalAlignment: Text.AlignRight
                            Layout.minimumWidth: root._wCpu
                            Layout.preferredWidth: root._wCpu
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
                                Quickshell.execDetached(["bash", "-c",
                                    "printf '%s' \"$1\" | wl-copy", "_",
                                    modelData.pid + " " + modelData.name]);
                                return;
                            }
                            if (m.modifiers & Qt.ShiftModifier) {
                                Quickshell.execDetached(["kill", "-KILL", String(modelData.pid)]);
                                return;
                            }
                            root.armOrKill(modelData.pid);
                        }
                    }
                }
            }
        }
    }
}
