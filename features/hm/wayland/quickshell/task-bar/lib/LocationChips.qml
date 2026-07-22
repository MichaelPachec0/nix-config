import QtQuick
import QtQuick.Layouts
import "locations.js" as Locations

// A wrapping row of selectable location chips (pill toggles) bound to a shared
// weatherState.selectedId. Reused by the bar weather popup and the hub
// Calendar/Weather card so switching location in one place updates both. A Flow
// (not a RowLayout) so a growing city list wraps to another row instead of
// overflowing the narrow (250px) popup.
Flow {
    id: chips

    required property QtObject theme
    required property var weatherState

    Layout.fillWidth: true
    spacing: 6

    Repeater {
        model: Locations.list
        Rectangle {
            id: chip
            required property var modelData
            readonly property bool sel: chips.weatherState.selectedId === chip.modelData.id

            implicitWidth: lbl.implicitWidth + 18
            implicitHeight: 20
            radius: height / 2
            color: chip.sel ? chips.theme.accent : chips.theme.bgItem
            border.width: 1
            border.color: chip.sel ? chips.theme.accent : chips.theme.border
            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }

            Text {
                id: lbl
                anchors.centerIn: parent
                text: chip.modelData.label
                color: chip.sel ? chips.theme.textOnAccent : chips.theme.textSecondary
                font.family: chips.theme.textFont
                font.pixelSize: 10
                font.weight: chip.sel ? Font.DemiBold : Font.Normal
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: chips.weatherState.selectedId = chip.modelData.id
            }
        }
    }
}
