import QtQuick
import "../lib" as Lib

// Bar keep-awake icon (idle concern): coffee mug. Icon-only -- the countdown is
// rendered by AwakeCluster (which consolidates the two icons' timers when they
// share an expiry). State comes from the shared InhibitService (svc); the
// IdleInhibitor lives in AwakeCluster. Click quick-toggles idle to its default
// (both, if locked); hover (handled by AwakeCluster) opens the popup.
Item {
    id: root

    required property QtObject theme
    required property var svc

    readonly property bool active: root.svc.idleOn

    implicitWidth: icon.implicitWidth
    implicitHeight: 24

    Lib.BarText {
        id: icon
        anchors.centerIn: parent
        // fa mug-hot (steaming) while inhibiting, mug-saucer (plain) at rest.
        text: String.fromCodePoint(root.active ? 0xF7B6 : 0xF0F4)
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
        onClicked: root.svc.toggle("idle")
    }
}
