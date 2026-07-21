import QtQuick
import QtQuick.Layouts
import "../lib/sysfmt.js" as SysFmt

// One SMU power/current utilisation row (PPT/STAPM/TDC/EDC): a label, a
// "cur / limit <unit>" readout, and a fill bar whose length + colour track
// cur/limit. The four rows differed only in label, value pair, and unit, which
// is why they were four near-identical copies.
RowLayout {
    id: barRoot

    required property QtObject theme
    required property string label
    required property real value
    required property real limit
    required property string unit   // "W" (power) or "A" (current)

    readonly property real fraction: barRoot.limit > 0
        ? Math.min(1, Math.max(0, barRoot.value / barRoot.limit)) : 0

    Layout.fillWidth: true
    spacing: 6

    Text {
        text: barRoot.label
        font.family: barRoot.theme.iconFont
        font.pixelSize: 10
        color: barRoot.theme.textPrimary
        Layout.preferredWidth: 40
    }
    Text {
        text: Math.round(barRoot.value) + " / " + Math.round(barRoot.limit) + " " + barRoot.unit
        font.family: barRoot.theme.iconFont
        font.pixelSize: 10
        color: SysFmt.sevColor(barRoot.theme, SysFmt.severity("cpu", barRoot.fraction * 100))
        Layout.fillWidth: true
    }
    Rectangle {
        implicitWidth: 70
        implicitHeight: 6
        radius: 2
        color: barRoot.theme.subtleFill
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * barRoot.fraction
            radius: parent.radius
            color: SysFmt.sevColor(barRoot.theme, SysFmt.severity("cpu", barRoot.fraction * 100))
        }
    }
}
