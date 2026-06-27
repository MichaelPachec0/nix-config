import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications

// A single toast popup card. Auto-dismisses after a timeout (critical urgency is
// sticky); hovering pauses the timer; clicking dismisses the notification. The
// toast only leaves the popup queue -- it stays in the hub list unless dismissed.
Rectangle {
    id: toast

    required property QtObject theme
    required property var notif        // Lib.NotifService
    required property var notification // Quickshell Notification

    readonly property bool critical: toast.notification.urgency === NotificationUrgency.Critical

    implicitHeight: row.implicitHeight + 24
    radius: toast.theme.radiusOuter
    color: toast.theme.bgCard
    border.width: 1
    border.color: toast.critical ? toast.theme.accentRed : toast.theme.border

    // Soft drop shadow.
    Rectangle {
        z: -1
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius
        color: "black"
        opacity: 0.25
    }

    opacity: 0
    Component.onCompleted: toast.opacity = 1
    Behavior on opacity {
        NumberAnimation {
            duration: 180
        }
    }

    // Auto-dismiss (paused on hover; critical urgency never auto-dismisses).
    Timer {
        interval: 5000
        running: !toast.critical && !hover.hovered
        onTriggered: toast.notif.removeToast(toast.notification)
    }

    HoverHandler {
        id: hover
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        // Left click dismisses for good; middle click just clears the toast.
        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton)
                toast.notif.removeToast(toast.notification);
            else
                toast.notification.dismiss();
        }
    }

    RowLayout {
        id: row
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 12
            rightMargin: 12
        }
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignTop
            width: 30
            height: 30
            radius: 999
            color: toast.critical ? Qt.rgba(toast.theme.accentRed.r, toast.theme.accentRed.g, toast.theme.accentRed.b, 0.16) : toast.theme.subtleFill
            Text {
                anchors.centerIn: parent
                text: String.fromCodePoint(0xF009A) // mdi bell
                font.family: toast.theme.iconFont
                font.pixelSize: 15
                color: toast.critical ? toast.theme.accentRed : toast.theme.accent
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: String(toast.notification.appName).toUpperCase().replace(/\n/g, ' ')
                font.family: toast.theme.textFont
                font.pixelSize: 9
                font.weight: Font.Bold
                color: toast.critical ? toast.theme.accentRed : toast.theme.textSecondary
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: toast.notification.summary.replace(/\n/g, ' ')
                font.family: toast.theme.textFont
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: toast.theme.textPrimary
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: toast.notification.body !== ""
                text: toast.notification.body.replace(/\n/g, ' ')
                font.family: toast.theme.textFont
                font.pixelSize: 11
                color: toast.theme.textSecondary
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }
    }
}
