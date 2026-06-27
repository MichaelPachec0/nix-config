import QtQuick
import QtQuick.Layouts

// One notification row in the hub NotificationsCard. Shows app / summary / body
// with a bell glyph (red for critical urgency), and dismisses on click. Adapted
// from surface-dots (Gruvbox theme tokens; ripple/overshoot dropped).
Rectangle {
    id: root

    required property QtObject theme
    required property string app
    required property string summary
    required property string body
    property bool critical: false

    signal dismissRequested

    implicitHeight: contentRow.implicitHeight + 22
    radius: 12
    color: hover.hovered ? root.theme.bgItemHover : root.theme.bgItem
    Behavior on color {
        ColorAnimation {
            duration: 140
        }
    }

    HoverHandler {
        id: hover
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismissRequested()
    }

    RowLayout {
        id: contentRow
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 11
            rightMargin: 11
        }
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignTop
            width: 28
            height: 28
            radius: 999
            color: root.critical ? Qt.rgba(root.theme.accentRed.r, root.theme.accentRed.g, root.theme.accentRed.b, 0.16) : root.theme.subtleFill
            Text {
                anchors.centerIn: parent
                text: String.fromCodePoint(0xF009A) // mdi bell
                font.family: root.theme.iconFont
                font.pixelSize: 14
                color: root.critical ? root.theme.accentRed : root.theme.accent
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: String(root.app).toUpperCase().replace(/\n/g, ' ')
                font.family: root.theme.textFont
                font.pixelSize: 9
                font.weight: Font.Bold
                color: root.critical ? root.theme.accentRed : root.theme.textSecondary
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: root.summary.replace(/\n/g, ' ')
                font.family: root.theme.textFont
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: root.theme.textPrimary
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: root.body !== ""
                text: root.body.replace(/\n/g, ' ')
                font.family: root.theme.textFont
                font.pixelSize: 11
                color: root.theme.textSecondary
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
            }
        }
    }
}
