import QtQuick
import QtQuick.Layouts

// A quick-settings toggle button: rounded fill (accent when active), squish on
// press, a hover overlay, and a glyph icon + small label. Left-click emits
// clicked(); right-click emits rightClicked(). Adapted from surface-dots with
// the icon as a glyph (caller passes `icon`) instead of an SVG + ColorOverlay.
Item {
    id: root

    required property QtObject theme
    property string icon: "" // a glyph (from the caller)
    property string label: ""
    property bool active: false

    signal clicked
    signal rightClicked

    Layout.fillWidth: true
    implicitHeight: 54

    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: mouse.pressed ? 0.9 : 1.0
        yScale: mouse.pressed ? 0.9 : 1.0
        Behavior on xScale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutBack
            }
        }
        Behavior on yScale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutBack
            }
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 9
        color: root.active ? root.theme.accent : root.theme.bgItem
        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }

        // Hover overlay (darken when active, lighten when not).
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root.active ? "black" : "white"
            opacity: mouse.containsMouse ? (root.active ? 0.10 : 0.08) : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.icon
                font.family: root.theme.iconFont
                font.pixelSize: 20
                color: root.active ? root.theme.textOnAccent : root.theme.textPrimary
                scale: mouse.containsMouse ? 1.18 : 1.0
                Behavior on scale {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutBack
                    }
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: root.width - 8
                text: root.label
                font.family: root.theme.textFont
                font.pixelSize: 9
                font.weight: Font.Medium
                opacity: root.active ? 0.9 : 0.7
                color: root.active ? root.theme.textOnAccent : root.theme.textPrimary
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => m.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
}
