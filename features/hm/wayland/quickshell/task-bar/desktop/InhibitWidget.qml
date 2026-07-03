import QtQuick
import "../lib" as Lib
import Quickshell
import Quickshell.Wayland

// Bar toggle that inhibits the lock screen / idle. Uses the Wayland idle-inhibit
// protocol attached to the bar surface, which swayidle honors through the
// compositor -- so toggling it engages/releases instantly with no daemon
// restarts. Click to keep the session awake; the coffee icon turns red while
// active. Hover shows a small state tooltip. Defaults off; in-memory.
Item {
    id: root

    required property QtObject theme
    required property var barWindow

    property bool active: false

    implicitWidth: 18
    implicitHeight: 24

    IdleInhibitor {
        window: root.barWindow
        enabled: root.active
    }

    Lib.BarText {
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
        onClicked: root.active = !root.active
        onContainsMouseChanged: containsMouse ? tip.show() : tip.hide()
    }

    // Small hover tooltip.
    PopupWindow {
        id: tip

        implicitWidth: tipText.implicitWidth + 20
        implicitHeight: tipText.implicitHeight + 12
        color: "transparent"
        visible: false
        grabFocus: false

        anchor.window: root.barWindow
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom | Edges.Right

        function show() {
            if (tip.visible)
                return;
            var x = root.mapToItem(null, 0, 0).x;
            tip.anchor.rect.x = Math.max(4, Math.min(x, root.barWindow.width - tip.implicitWidth - 8));
            tip.anchor.rect.y = root.barWindow.height + 4;
            tip.anchor.rect.width = 0;
            tip.anchor.rect.height = 0;
            tip.visible = true;
        }
        function hide() {
            tip.visible = false;
        }

        Rectangle {
            anchors.fill: parent
            radius: root.theme.radiusOuter
            color: root.theme.bgCard
            border.width: 1
            border.color: root.theme.border
            Text {
                id: tipText
                anchors.centerIn: parent
                text: root.active ? "Keep awake: on" : "Keep awake: off"
                color: root.theme.textPrimary
                font.family: root.theme.iconFont
                font.pixelSize: 11
            }
        }
    }
}
