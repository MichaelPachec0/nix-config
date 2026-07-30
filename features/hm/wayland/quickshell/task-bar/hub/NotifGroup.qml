import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import "../lib/notiftime.js" as NotifTime

// One app's notifications as a group widget. Header: app name (left) + a count
// badge, an expand/collapse toggle (2+ items), and a wipe-all button. Body:
// collapsed -> all cards z-stacked into a deck (newest on top); expanded -> a
// full vertical list. Shared by the hub panel and the toast overlay (toastMode
// enables per-card auto-dismiss timers and makes wipe clear only the toast).
//
// Collapsed clicks: the top card dismisses itself; a click on the peeking cards
// (which are non-interactive) falls through to the expand catcher and expands.
Rectangle {
    id: group

    required property QtObject theme
    required property var notif  // Lib.NotifService
    required property var entry  // { app, list }
    property bool toastMode: false
    property int peekOffset: 7
    readonly property int cardH: 50 // must match NotifItem compact height

    readonly property var list: group.entry.list
    // Identical-content stacks (see lib/notifstack.js). Every card below stands
    // for one STACK, so a chatty app collapses to one card with an "xN" badge
    // instead of N visually identical ones.
    readonly property var stacks: group.notif.stacksOf(group.list)
    // `total` drives the header badge (the user counts notifications, not
    // stacks); `stackCount` drives the deck geometry and the expand toggle
    // (they are about how many CARDS there are).
    readonly property int total: group.list.length
    readonly property int stackCount: group.stacks.length
    readonly property bool expanded: group.notif.isExpanded(group.entry.app)
    // Stacked deck only makes sense for 2+ cards; a lone card renders full so
    // its body and action buttons are reachable.
    readonly property bool useDeck: group.stackCount > 1 && !group.expanded
    readonly property bool hasCritical: {
        for (var i = 0; i < group.list.length; i++)
            if (group.list[i].urgency === NotificationUrgency.Critical)
                return true;
        return false;
    }

    radius: group.theme.radiusOuter
    color: group.theme.bgCard
    border.width: 1
    border.color: group.hasCritical ? group.theme.accentRed : group.theme.border
    implicitHeight: col.implicitHeight + 20

    function wipe() {
        if (group.toastMode)
            group.notif.removeToastApp(group.entry.app);
        else
            group.notif.dismissApp(group.entry.app);
    }

    ColumnLayout {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 8

        // Header: app name + count badge + expand toggle + wipe.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                Layout.fillWidth: true
                text: String(group.entry.app).toUpperCase().replace(/\n/g, ' ')
                color: group.hasCritical ? group.theme.accentRed : group.theme.textSecondary
                font.family: group.theme.textFont
                font.pixelSize: 10
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            Rectangle {
                visible: group.total > 1
                radius: 999
                color: group.theme.bgItem
                implicitHeight: 18
                implicitWidth: cnt.implicitWidth + 12
                Layout.alignment: Qt.AlignVCenter
                Text {
                    id: cnt
                    anchors.centerIn: parent
                    text: group.total
                    color: group.theme.textSecondary
                    font.family: group.theme.textFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
            }
            GroupBtn {
                visible: group.stackCount > 1
                glyph: group.expanded ? 0xF0143 : 0xF0140 // chevron up / down
                onActivated: group.notif.toggleExpanded(group.entry.app)
            }
            GroupBtn {
                glyph: 0xF0A7A // trash-can-outline
                danger: true
                onActivated: group.wipe()
            }
        }

        // Body: stacked deck (collapsed) or full list (expanded).
        Item {
            Layout.fillWidth: true
            implicitHeight: group.useDeck ? stackBody.implicitHeight : expandedCol.implicitHeight
            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            // Collapsed: z-stacked deck. Newest stack (index 0) on top.
            Item {
                id: stackBody
                visible: group.useDeck
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: group.stackCount > 0 ? (group.cardH + (group.stackCount - 1) * group.peekOffset) : 0

                // Catches clicks on the peeking (non-interactive) cards -> expand.
                MouseArea {
                    anchors.fill: parent
                    enabled: group.stackCount > 1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: group.notif.toggleExpanded(group.entry.app)
                }

                Repeater {
                    // Only the visible branch builds delegates; the hidden branch
                    // gets an empty model so it doesn't instantiate a second full
                    // set of NotifItems (each with its own async images).
                    model: group.useDeck ? group.stacks : []
                    NotifItem {
                        id: stackCard
                        required property var modelData // a stack
                        required property int index
                        readonly property var newest: stackCard.modelData.list[0]
                        width: stackBody.width
                        height: group.cardH
                        y: stackCard.index * group.peekOffset
                        z: group.stackCount - stackCard.index
                        compact: true
                        interactive: stackCard.index === 0 // only the top card
                        theme: group.theme
                        source: stackCard.newest
                        app: group.notif.keyOf(stackCard.newest)
                        summary: stackCard.newest.summary
                        body: stackCard.newest.body
                        critical: stackCard.newest.urgency === NotificationUrgency.Critical
                        stackCount: stackCard.modelData.count
                        // Reads group.notif.nowMs so the age repaints on the
                        // shared 30s tick. The hub has no 12/24h setting, so 24h.
                        stamp: NotifTime.fmtStamp(group.notif.nowMs, stackCard.modelData.newest, false)
                        onDismissRequested: group.notif.dismissStack(stackCard.modelData)
                    }
                }
            }

            // Expanded: full vertical list, still one card per stack.
            ColumnLayout {
                id: expandedCol
                visible: !group.useDeck
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6
                Repeater {
                    model: group.useDeck ? [] : group.stacks
                    NotifItem {
                        id: listCard
                        required property var modelData // a stack
                        readonly property var newest: listCard.modelData.list[0]
                        Layout.fillWidth: true
                        compact: false
                        interactive: true
                        theme: group.theme
                        source: listCard.newest
                        app: group.notif.keyOf(listCard.newest)
                        summary: listCard.newest.summary
                        body: listCard.newest.body
                        critical: listCard.newest.urgency === NotificationUrgency.Critical
                        stackCount: listCard.modelData.count
                        stamp: NotifTime.fmtStamp(group.notif.nowMs, listCard.modelData.newest, false)
                        onDismissRequested: group.notif.dismissStack(listCard.modelData)
                    }
                }
            }
        }
    }

    // Small square icon button used in the header.
    component GroupBtn: Rectangle {
        id: btn
        property int glyph: 0
        property bool danger: false
        signal activated

        implicitWidth: 26
        implicitHeight: 22
        radius: 7
        Layout.alignment: Qt.AlignVCenter
        color: {
            if (btn.danger)
                return btnHover.hovered ? Qt.rgba(group.theme.accentRed.r, group.theme.accentRed.g, group.theme.accentRed.b, 0.18) : Qt.rgba(group.theme.accentRed.r, group.theme.accentRed.g, group.theme.accentRed.b, 0.1);
            return btnHover.hovered ? group.theme.bgItemHover : group.theme.bgItem;
        }
        Behavior on color {
            ColorAnimation {
                duration: 140
            }
        }
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(btn.glyph)
            font.family: group.theme.iconFont
            font.pixelSize: 13
            color: btn.danger ? group.theme.accentRed : group.theme.textSecondary
        }
        HoverHandler {
            id: btnHover
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }
}
