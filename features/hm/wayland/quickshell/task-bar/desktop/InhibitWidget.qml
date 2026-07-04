import QtQuick
import "../lib" as Lib
import QtQuick.Layouts

// Bar keep-awake icon (idle concern): coffee mug + a fixed-width countdown slot.
// State comes from the shared InhibitService (svc); the actual IdleInhibitor
// lives in AwakeCluster (it needs the bar window). Click quick-toggles idle to
// indefinite (both, if locked); hover (handled by AwakeCluster) opens the popup.
Item {
    id: root

    required property QtObject theme
    required property var barWindow
    required property var svc

    readonly property bool active: root.svc.idleOn

    implicitWidth: row.implicitWidth
    implicitHeight: 24

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 4

        Lib.BarText {
            Layout.alignment: Qt.AlignVCenter
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

        // Fixed-width timer slot: width of "00:00:00" so counting never shifts
        // the pill; centered content is the countdown, an infinity mark when
        // indefinite, or empty (hidden) when off.
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
                text: root.svc.countdownText("idle")
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
        onClicked: root.svc.toggleIndefinite("idle")
    }
}
