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
            }
        }
    }
}
