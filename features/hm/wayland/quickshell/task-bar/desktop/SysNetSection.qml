import QtQuick
import QtQuick.Layouts
import "../lib/sysfmt.js" as SysFmt

// Network section: per-interface download/upload rates.
// Hidden when net.available is false (no active interfaces found).
ColumnLayout {
    id: root
    spacing: 4
    visible: root.net.available

    required property QtObject theme
    required property var net

    // Reserve room for the widest rate string so a rate crossing a unit/digit
    // boundary (e.g. 999 B/s -> 1.4 K/s) never widens the row and pushes it out.
    readonly property real _wRate: _mRate.advanceWidth
    TextMetrics { id: _mRate; font.family: root.theme.iconFont; font.pixelSize: 10; text: "dn 999.9 M/s   up 999.9 M/s" }

    // Header
    Text {
        text: "Network"
        font.family: root.theme.iconFont; font.pixelSize: 11; font.weight: Font.DemiBold
        color: root.theme.textSecondary
    }

    // Per-interface rows
    Repeater {
        model: root.net.ifaces
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 6

            // Interface name
            Text {
                text: modelData.name
                font.family: root.theme.iconFont; font.pixelSize: 10
                color: root.theme.textPrimary
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // dn / up rates
            Text {
                text: "dn " + SysFmt.fmtRate(modelData.rx) + "   up " + SysFmt.fmtRate(modelData.tx)
                font.family: root.theme.iconFont; font.pixelSize: 10
                color: root.theme.textSecondary
                horizontalAlignment: Text.AlignRight
                Layout.minimumWidth: root._wRate
                Layout.preferredWidth: root._wRate
            }
        }
    }
}
