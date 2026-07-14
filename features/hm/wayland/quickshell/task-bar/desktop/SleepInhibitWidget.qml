import QtQuick
import "../lib" as Lib

// Bar prevent-sleep icon (sleep concern): bed glyph. Icon-only -- the countdown
// is rendered by AwakeCluster (which consolidates the two icons' timers when
// they share an expiry). State + the systemd-inhibit engagement live in the
// shared InhibitService (svc). Click quick-toggles sleep to its default (both,
// if locked); hover (handled by AwakeCluster) opens the popup.
Item {
    id: root

    required property QtObject theme
    required property var svc

    readonly property bool active: root.svc.sleepOn

    implicitWidth: icon.implicitWidth
    implicitHeight: 24

    Lib.BarText {
        id: icon
        anchors.centerIn: parent
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

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.svc.toggle("sleep")
    }
}
