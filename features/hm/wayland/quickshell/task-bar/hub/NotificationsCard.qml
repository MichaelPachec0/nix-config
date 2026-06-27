import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications

// Hub notifications list (Phase 2f, step 8). Backed by the live QS notification
// server (NotifService.server.trackedNotifications) instead of dunstctl. Header
// with a count badge + Clear-all, an empty state, and a scrollable list of
// NotifItem rows; click a row to dismiss it.
Rectangle {
    id: root

    required property QtObject theme
    required property var notif // Lib.NotifService

    readonly property var items: root.notif ? root.notif.items : []
    readonly property int count: root.notif ? root.notif.count : 0

    implicitHeight: col.implicitHeight + 24
    radius: root.theme.radiusOuter
    color: root.theme.bgCard
    border.width: 1
    border.color: root.theme.border

    ColumnLayout {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 8

        // Header: title + count badge + Clear-all.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: "Notifications"
                color: root.theme.textPrimary
                font.family: root.theme.textFont
                font.pixelSize: 13
                font.weight: Font.Bold
            }
            Rectangle {
                radius: 999
                color: root.theme.bgItem
                implicitHeight: 20
                implicitWidth: cnt.implicitWidth + 16
                Layout.alignment: Qt.AlignVCenter
                Text {
                    id: cnt
                    anchors.centerIn: parent
                    text: String(root.count)
                    color: root.theme.textSecondary
                    font.family: root.theme.textFont
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
            }
            Rectangle {
                visible: root.count > 0
                radius: 8
                implicitHeight: 22
                implicitWidth: 48
                color: clearHover.hovered ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.18) : Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.1)
                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: "Clear"
                    color: root.theme.accentRed
                    font.family: root.theme.textFont
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                HoverHandler {
                    id: clearHover
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.notif.dismissAll()
                }
            }
        }

        // Empty state.
        Text {
            Layout.fillWidth: true
            visible: root.count === 0
            text: "No new notifications"
            horizontalAlignment: Text.AlignHCenter
            color: root.theme.textSecondary
            font.family: root.theme.textFont
            font.pixelSize: 11
            font.italic: true
            topPadding: 4
            bottomPadding: 4
        }

        // Notifications grouped by app. A plain Column (not a ListView) so the
        // hub overlay's outer Flickable owns all scrolling -- no nested scroller.
        ColumnLayout {
            id: groupList
            visible: root.count > 0
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: root.notif ? root.notif.groups : []
                NotifGroup {
                    required property var modelData
                    Layout.fillWidth: true
                    theme: root.theme
                    notif: root.notif
                    entry: modelData
                }
            }
        }
    }
}
