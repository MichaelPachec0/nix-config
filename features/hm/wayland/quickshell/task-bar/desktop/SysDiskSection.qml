import QtQuick
import QtQuick.Layouts
import "../lib/sysfmt.js" as SysFmt

// Disk section: per-mount usage bars + aggregate read/write rates.
// Hidden when disk.available is false (no real mounts found).
ColumnLayout {
    id: root
    spacing: 4
    visible: root.disk.available

    required property QtObject theme
    required property var disk

    // Header
    Text {
        text: "Disk"
        font.family: root.theme.iconFont; font.pixelSize: 11; font.weight: Font.DemiBold
        color: root.theme.textSecondary
    }

    // Per-mount rows
    Repeater {
        model: root.disk.mounts
        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 2

            // Mount target label
            Text {
                text: modelData.target
                font.family: root.theme.iconFont; font.pixelSize: 10
                color: root.theme.textPrimary
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // Usage bar (mem-bar style)
            Rectangle {
                Layout.fillWidth: true
                height: 6
                radius: 2
                color: Qt.rgba(root.theme.textSecondary.r, root.theme.textSecondary.g,
                               root.theme.textSecondary.b, 0.15)
                Rectangle {
                    width: parent.width * Math.min(modelData.pct, 100) / 100
                    height: parent.height
                    radius: parent.radius
                    color: SysFmt.sevColor(root.theme,SysFmt.severity("mem", modelData.pct))
                }
            }

            // Used / size / pct detail
            Text {
                text: SysFmt.fmtKB(modelData.usedKB) + " / " + SysFmt.fmtKB(modelData.sizeKB)
                    + "  (" + modelData.pct + "%)"
                font.family: root.theme.iconFont; font.pixelSize: 10
                color: root.theme.textSecondary
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    // Aggregate I/O rates
    Text {
        Layout.fillWidth: true
        text: "rd " + SysFmt.fmtRate(root.disk.readRate) + "   wr " + SysFmt.fmtRate(root.disk.writeRate)
        font.family: root.theme.iconFont; font.pixelSize: 10
        color: root.theme.textSecondary
        elide: Text.ElideRight
    }
}
