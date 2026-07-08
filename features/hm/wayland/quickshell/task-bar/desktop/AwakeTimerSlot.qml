import QtQuick
import "../lib" as Lib

// Fixed-width countdown slot (width of "00:00:00" so counting never shifts the
// pill). Shows `label` (HH:MM:SS countdown or the infinity mark) centered.
// Shared by the awake bar icons; instanced + shown/hidden by AwakeCluster, which
// consolidates the two concerns' timers into one when they share an expiry.
Item {
    id: slot

    required property QtObject theme
    property string label: ""

    implicitWidth: slotMetrics.advanceWidth
    implicitHeight: 24

    TextMetrics {
        id: slotMetrics
        font.family: slot.theme.iconFont
        font.pixelSize: 10
        text: "00:00:00"
    }
    Lib.BarText {
        anchors.centerIn: parent
        text: slot.label
        color: slot.theme.textPrimary
        font.family: slot.theme.iconFont
        font.pixelSize: 10
    }
}
