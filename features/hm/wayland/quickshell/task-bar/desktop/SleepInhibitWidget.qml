import QtQuick
import "../lib" as Lib
import Quickshell
import Quickshell.Io

// Bar toggle that blocks system suspend/hibernate via a systemd-logind "block"
// inhibitor. This is a separate concern from the keep-awake widget: keep-awake
// uses the Wayland idle-inhibit protocol to stop the screen blanking / lock,
// whereas this keeps the *machine* from sleeping. The two own their own state
// and do not interact. Defaults off; in-memory. Click to disable sleep; the bed
// icon turns red while active.
Item {
    id: root

    required property QtObject theme
    required property var barWindow

    property bool active: false

    implicitWidth: 18
    implicitHeight: 24

    // The logind lock is held for exactly as long as this process runs:
    // systemd-inhibit takes the block inhibitor, then `sleep infinity` keeps it
    // held until we stop it (SIGTERM on running=false), which releases the lock.
    // Runs as the user -- no root/polkit -- and auto-releases on shell reload.
    //
    // Two inhibitor classes are needed. "sleep" (a high-level lock) blocks
    // idle-triggered auto-suspend, the sleep key, and other apps calling
    // suspend. But lid-close is exempt from high-level locks by default
    // (logind's LidSwitchIgnoreInhibited defaults to "yes"), so it would still
    // suspend on lid close. "handle-lid-switch" is a low-level lock that logind
    // *always* honors, which is what actually covers the lid.
    Process {
        id: inhibitor
        running: root.active
        command: ["systemd-inhibit", "--what=sleep:handle-lid-switch", "--who=Quickshell",
            "--why=Disable sleep toggle", "--mode=block", "sleep", "infinity"]
    }

    Lib.BarText {
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
                text: root.active ? "Disable sleep: on" : "Disable sleep: off"
                color: root.theme.textPrimary
                font.family: root.theme.iconFont
                font.pixelSize: 11
            }
        }
    }
}
