import QtQuick
import QtQuick.Layouts
import Quickshell

// Hover key-hints for the active submap, anchored under the mode pill (RouterPopup
// idiom). Read-only, grabFocus:false. contentHovered drives the pill's hide-bridge.
PopupWindow {
    id: pop
    required property QtObject theme
    required property var barWindow
    required property var anchorItem
    required property var svc

    property bool contentHovered: cardHover.hovered

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    color: "transparent"
    visible: false
    grabFocus: false
    anchor.window: pop.barWindow

    function reclamp() {
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.anchor.rect.x = Math.max(4, Math.min(x, pop.barWindow.width - pop.implicitWidth - 8));
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
    }
    function show() { if (!pop.visible) { pop.reclamp(); pop.visible = true; } }
    function hide() { pop.visible = false; }

    Rectangle {
        id: card
        implicitWidth: Math.max(col.implicitWidth + 24, 180)
        implicitHeight: col.implicitHeight + 24
        radius: pop.theme.radiusOuter
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border
        HoverHandler { id: cardHover }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 6

            Text {
                text: pop.svc ? pop.svc.label() : ""
                font.family: pop.theme.iconFont; font.pixelSize: 12; font.weight: Font.Bold
                color: pop.theme.textPrimary
            }
            Repeater {
                model: pop.svc ? pop.svc.keys() : []
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: modelData.k
                        font.family: pop.theme.iconFont; font.pixelSize: 11; font.weight: Font.DemiBold
                        color: pop.theme.textPrimary
                        Layout.minimumWidth: 96
                    }
                    Text {
                        text: modelData.d
                        font.family: pop.theme.iconFont; font.pixelSize: 11
                        color: pop.theme.textSecondary
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
