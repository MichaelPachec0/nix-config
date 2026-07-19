import QtQuick
import QtQuick.Layouts
import "../lib/sysfmt.js" as SysFmt
import "../lib/sensormerge.js" as SensorMerge

// Sensor/temperature section: every populated temp from SensorStats, laid out in
// a two-column grid, each value colorized by temp severity (green/yellow/red).
// Hidden when no sensors are available.
ColumnLayout {
    id: root
    spacing: 4
    visible: (root.sensors && root.sensors.available) || (root.smu && root.smu.available)

    required property QtObject theme
    required property var sensors
    // Not `required`: it is fed by the parent layout's own `smu` binding, which
    // is undefined at this child's construction time. A required property would
    // fail creation ("failed to create variant") and never attach; a plain var
    // starts undefined and the binding attaches reactively once the popup wires
    // the provider through. The merge below already treats a null smu as absent.
    property var smu

    // Reserve room for a 3-digit temperature ("100 C") so a 2->3 digit change (or
    // 65 C vs 100 C across rows) keeps every value's column aligned and stable.
    readonly property real _wTemp: _mTemp.advanceWidth
    TextMetrics { id: _mTemp; font.family: root.theme.iconFont; font.pixelSize: 10; text: "100 C" }

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
            model: SensorMerge.mergeSensors(root.sensors ? root.sensors.sensors : [], root.smu ? { available: root.smu.available, cpu: root.smu.cpu, peak: root.smu.peak, soc: root.smu.soc, gfx: root.smu.gfx } : null)
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
                    color: SysFmt.sevColor(root.theme,SysFmt.severity("temp", modelData.temp))
                    horizontalAlignment: Text.AlignRight
                    Layout.minimumWidth: root._wTemp
                    Layout.preferredWidth: root._wTemp
                }
            }
        }
    }
}
