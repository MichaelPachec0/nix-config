import QtQuick
import QtQuick.Layouts
import "../lib/sysfmt.js" as SysFmt

// Sensor/temperature section: every populated temp from SensorStats, laid out in
// a two-column grid, each value colorized by temp severity (green/yellow/red).
// Hidden when no sensors are available.
ColumnLayout {
    id: root
    spacing: 4
    visible: root.sensors.available

    required property QtObject theme
    required property var sensors

    function sevColor(sev) {
        return sev === "good" ? theme.accentGreen
             : sev === "fair" ? theme.accentYellow : theme.accentRed;
    }

    Text {
        text: "Sensors"
        font.family: root.theme.iconFont
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: root.theme.textSecondary
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 14
        rowSpacing: 2
        Repeater {
            model: root.sensors.sensors
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1   // equal half-columns; content can't widen a column
                clip: true                 // hard stop: never render past this cell
                spacing: 6
                Text {
                    text: modelData.label
                    font.family: root.theme.iconFont
                    font.pixelSize: 10
                    color: root.theme.textPrimary
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: modelData.temp + " C"
                    font.family: root.theme.iconFont
                    font.pixelSize: 10
                    color: root.sevColor(SysFmt.severity("temp", modelData.temp))
                }
            }
        }
    }
}
