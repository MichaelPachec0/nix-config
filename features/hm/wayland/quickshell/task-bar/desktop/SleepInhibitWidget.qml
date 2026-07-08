import QtQuick
import "../lib" as Lib
import QtQuick.Layouts

// Bar prevent-sleep icon (sleep concern): bed glyph + a fixed-width countdown
// slot. State + the systemd-inhibit engagement live in the shared
// InhibitService (svc). Click quick-toggles sleep to indefinite (both, if
// locked); hover (handled by AwakeCluster) opens the popup.
Item {
    id: root

    required property QtObject theme
    required property var barWindow
    required property var svc

    readonly property bool active: root.svc.sleepOn

    implicitWidth: row.implicitWidth
    implicitHeight: 24

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 4

        Lib.BarText {
            Layout.alignment: Qt.AlignVCenter
            text: String.fromCodePoint(0xF236) // fa bed
            font.family: root.theme.faFont
            font.pixelSize: 13
            color: root.active ? root.theme.accentRed : (hover.containsMouse ? root.theme.textPrimary : root.theme.textSecondary)
            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            visible: root.active
            implicitWidth: slotMetrics.advanceWidth
            implicitHeight: 24
            TextMetrics {
                id: slotMetrics
                font.family: root.theme.iconFont
                font.pixelSize: 10
                text: "00:00:00"
            }
            Lib.BarText {
                anchors.centerIn: parent
                text: root.svc.countdownText("sleep")
                color: root.theme.textPrimary
                font.family: root.theme.iconFont
                font.pixelSize: 10
            }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.svc.toggle("sleep")
    }
}
