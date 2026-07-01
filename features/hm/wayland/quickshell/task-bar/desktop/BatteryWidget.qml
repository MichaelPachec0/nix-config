import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

// Bar battery widget (laptop only): a drawn battery with a charging/AC bolt
// overlay + percentage; hover shows a detailed popup. Reads UPower.displayDevice
// for charge/state and UPower.onBattery for AC. The bolt + charging tint show
// whenever plugged in (incl. charge-limited "not charging"), reflecting AC.
Item {
    id: root

    required property QtObject theme
    required property var barWindow // the bar PanelWindow, for popup anchoring

    readonly property var dev: UPower.displayDevice
    readonly property real pct: root.dev ? root.dev.percentage * 100 : 0
    readonly property bool onAC: UPower.onBattery === false
    readonly property bool low: !root.onAC && root.pct <= 20

    visible: root.dev !== null && root.dev.isLaptopBattery
    implicitWidth: row.implicitWidth
    implicitHeight: 24

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 5

        // Drawn battery: body + fill + terminal nub, with an AC/charging bolt.
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 25
            implicitHeight: 13
            Rectangle {
                id: batBody
                width: 22
                height: 13
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"
                border.width: 1.5
                border.color: root.low ? root.theme.accentRed : root.theme.textSecondary
                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(1, (batBody.width - 4) * Math.min(100, root.pct) / 100)
                    height: batBody.height - 4
                    radius: 1
                    color: root.low ? root.theme.accentRed : (root.onAC ? root.theme.accentSlider : root.theme.accent)
                }
                // Bolt while on AC. White with a soft offset shadow (a second
                // Text behind it, since GraphicalEffects is avoided here) so it
                // stays legible over both the green fill and the dark empty area
                // without the harsh orange-on-green vibration.
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 0.5
                    anchors.verticalCenterOffset: 0.75
                    visible: root.onAC
                    text: String.fromCodePoint(0xF0E7) // bolt (white halo/shadow)
                    color: Qt.rgba(1, 1, 1, 0.85)
                    font.family: root.theme.iconFont
                    font.pixelSize: 10
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.onAC
                    text: String.fromCodePoint(0xF0E7) // bolt
                    color: "#2e3436"
                    font.family: root.theme.iconFont
                    font.pixelSize: 9
                }
            }
            Rectangle {
                anchors.left: batBody.right
                anchors.verticalCenter: batBody.verticalCenter
                width: 2
                height: 5
                radius: 1
                color: root.low ? root.theme.accentRed : root.theme.textSecondary
            }
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: Math.round(root.pct) + "%"
            color: root.low ? root.theme.accentRed : (root.onAC ? root.theme.accentSlider : root.theme.textPrimary)
            font.family: root.theme.textFont
            font.pixelSize: 13
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onContainsMouseChanged: containsMouse ? popup.show() : popup.hide()
    }

    BatteryPopup {
        id: popup
        theme: root.theme
        barWindow: root.barWindow
        anchorItem: root
    }
}
