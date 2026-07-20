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
                delegate: ProcRow {
                    theme: root.theme
                    armedPid: root.armedPid
                    valueText: SysFmt.fmtKB(modelData.rssKB)
                    valueWidth: root._wMem
                    onArmOrKill: pid => root.armOrKill(pid)
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
                delegate: ProcRow {
                    theme: root.theme
                    armedPid: root.armedPid
                    valueText: modelData.pcpu + "%"
                    valueWidth: root._wCpu
                    onArmOrKill: pid => root.armOrKill(pid)
                }
            }
        }
    }
}
