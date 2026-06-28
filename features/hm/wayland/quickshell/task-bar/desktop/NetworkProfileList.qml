import QtQuick
import QtQuick.Layouts

// A profile list for one connection category (ethernet/vpn). Each row: name,
// up/down state, active highlight; the active row shows its IP + router. A
// footer shows the global Internet connectivity. Left-click brings a profile
// up; right-click toggles up/down.
ColumnLayout {
    id: list

    required property QtObject theme
    required property var net
    required property var conns        // [{uuid,name,type,active,ip,gateway}]
    property string emptyText: "No connections"

    spacing: 2

    function connColor() {
        switch (list.net.connectivity) {
        case "full":
            return list.theme.accentGreen;
        case "limited":
            return list.theme.accentOrange;
        case "portal":
            return list.theme.accentYellow;
        case "none":
            return list.theme.accentRed;
        default:
            return list.theme.textSecondary;
        }
    }

    Repeater {
        model: list.conns
        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: rowCol.implicitHeight + 12
            radius: 6
            color: rowHover.hovered ? list.theme.bgItemHover : (modelData.active ? Qt.rgba(list.theme.accent.r, list.theme.accent.g, list.theme.accent.b, 0.12) : "transparent")

            ColumnLayout {
                id: rowCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 1
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        color: modelData.active ? list.theme.textPrimary : list.theme.textSecondary
                        font.family: list.theme.textFont
                        font.pixelSize: 12
                        font.weight: modelData.active ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    Text {
                        text: modelData.active ? "up" : "down"
                        color: modelData.active ? list.theme.accentGreen : list.theme.textSecondary
                        font.family: list.theme.textFont
                        font.pixelSize: 10
                    }
                }
                Text {
                    visible: modelData.active && modelData.ip !== ""
                    Layout.fillWidth: true
                    text: modelData.ip + (modelData.gateway !== "" ? "  .  via " + modelData.gateway : "")
                    color: list.theme.textSecondary
                    font.family: list.theme.textFont
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
            HoverHandler {
                id: rowHover
                cursorShape: Qt.PointingHandCursor
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function (e) {
                    if (e.button === Qt.RightButton)
                        list.net.toggleConn(modelData.uuid, !modelData.active);
                    else
                        list.net.toggleConn(modelData.uuid, true);
                }
            }
        }
    }

    // Empty state.
    Text {
        visible: list.conns.length === 0
        Layout.fillWidth: true
        text: list.emptyText
        color: list.theme.textSecondary
        font.family: list.theme.textFont
        font.pixelSize: 12
    }

    // Footer: global Internet connectivity.
    Text {
        visible: list.conns.length > 0
        Layout.fillWidth: true
        Layout.topMargin: 4
        text: "Internet: " + list.net.connectivity
        color: list.connColor()
        font.family: list.theme.textFont
        font.pixelSize: 10
    }
}
