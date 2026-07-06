import QtQuick
import QtQuick.Layouts
import "../lib" as Lib
import "../lib/sysfmt.js" as SysFmt

// CPU section: header row (util, load, temp), per-core mini bars, history sparkline.
// Consumed by the SysPopup composition layer. No visible gate (CPU always present).
ColumnLayout {
    id: root
    spacing: 6

    required property QtObject theme
    required property var stats

    function sevColor(sev) {
        return sev === "good" ? theme.accentGreen
             : sev === "fair" ? theme.accentYellow : theme.accentRed;
    }

    // Header: CPU%, load averages, temperature
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Text {
            text: "CPU " + Math.round(root.stats.cpuPct) + "%"
            font.family: root.theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold
            color: root.sevColor(SysFmt.severity("cpu", root.stats.cpuPct))
        }
        Text {
            text: "load " + (root.stats.load[0] || 0).toFixed(2) + " "
                + (root.stats.load[1] || 0).toFixed(2) + " " + (root.stats.load[2] || 0).toFixed(2)
            font.family: root.theme.iconFont; font.pixelSize: 11
            color: root.theme.textSecondary
        }
        Item { Layout.fillWidth: true }
        Text {
            text: "zen " + Math.round(root.stats.cpuTemp) + " C"
            font.family: root.theme.iconFont; font.pixelSize: 11
            color: root.sevColor(SysFmt.severity("temp", root.stats.cpuTemp))
        }
    }

    // Per-core mini bars
    Row {
        Layout.fillWidth: true
        spacing: 2
        Repeater {
            model: root.stats.perCore
            delegate: Rectangle {
                required property int index
                required property var modelData
                width: 6
                height: 16
                radius: 1
                color: Qt.rgba(root.theme.textSecondary.r, root.theme.textSecondary.g,
                               root.theme.textSecondary.b, 0.2)
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(1, parent.height * modelData / 100)
                    radius: 1
                    color: root.sevColor(SysFmt.severity("cpu", modelData))
                }
            }
        }
    }

    // History sparkline
    Lib.Sparkline {
        Layout.fillWidth: true
        implicitHeight: 22
        values: root.stats.cpuHist
        color: root.theme.accent
    }
}
