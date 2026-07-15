import QtQuick
import "../lib" as Lib
import "../lib/inhibitlogic.js" as InhibitLogic

// Fixed-width countdown slot (width of "00:00:00" so counting never shifts the
// pill). Shows `label` (HH:MM:SS countdown or the infinity mark) centered.
// Shared by the awake bar icons; instanced + shown/hidden by AwakeCluster, which
// consolidates the two concerns' timers into one when they share an expiry.
Item {
    id: slot

    required property QtObject theme
    property string label: ""

    // The indefinite mark renders larger than the countdown for prominence; the
    // fixed width (TextMetrics of "00:00:00" at 10px) is unaffected, so the wider
    // glyph just re-centers in the same box and the pill never shifts.
    readonly property bool isInfinity: slot.label === InhibitLogic.infinityGlyph()

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
        font.pixelSize: slot.isInfinity ? 19 : 10
    }
}
