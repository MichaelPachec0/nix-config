import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A fat rounded slider (M3-expressive style): the track fills with the accent
// as the value rises, with an icon glyph anchored at the low end. Supports
// horizontal or vertical orientation. The handle is hidden. Adapted from
// surface-dots, with the icon as a Nerd Font glyph (caller passes `icon`)
// rather than an SVG + ColorOverlay, dropping the GraphicalEffects dependency.
Item {
    id: root

    required property QtObject theme
    property string icon: "" // a Nerd Font glyph (from the caller)
    property real from: 0
    property real to: 100
    property alias value: slider.value
    property bool pressed: slider.pressed
    property int orientation: Qt.Horizontal
    property color accentColor: root.theme.accentSlider

    // Fill fraction straight from value (0 at `from`, 1 at `to`) -- avoids the
    // orientation-dependent flip of Slider.visualPosition for vertical sliders.
    readonly property real frac: (slider.value - root.from) / Math.max(0.0001, root.to - root.from)
    signal userChanged(real v)

    implicitHeight: orientation === Qt.Horizontal ? 32 : 100
    implicitWidth: orientation === Qt.Horizontal ? 100 : 32
    Layout.fillWidth: orientation === Qt.Horizontal
    Layout.fillHeight: orientation === Qt.Vertical

    // Debounce: report changes shortly after the last move so we don't spam the
    // backend (brightnessctl / PipeWire) on every pixel, while staying snappy.
    Timer {
        id: send
        interval: 30
        onTriggered: root.userChanged(slider.value)
    }

    Slider {
        id: slider
        anchors.fill: parent
        from: root.from
        to: root.to
        orientation: root.orientation
        hoverEnabled: true
        onMoved: send.restart()
        onPressedChanged: if (!pressed)
            send.restart()

        background: Rectangle {
            x: root.orientation === Qt.Horizontal ? slider.leftPadding : (slider.availableWidth - width) / 2
            y: root.orientation === Qt.Horizontal ? (slider.availableHeight - height) / 2 : slider.topPadding
            width: root.orientation === Qt.Horizontal ? slider.availableWidth : 32
            height: root.orientation === Qt.Horizontal ? 32 : slider.availableHeight
            radius: 16
            color: root.theme.bgItem

            // Accent fill, growing with the value (from the low end: left for
            // horizontal, bottom for vertical).
            Rectangle {
                width: root.orientation === Qt.Horizontal ? (root.frac * parent.width) : parent.width
                height: root.orientation === Qt.Horizontal ? parent.height : (root.frac * parent.height)
                y: root.orientation === Qt.Horizontal ? 0 : parent.height - height
                radius: 16
                color: root.accentColor
                opacity: 0.2 + (root.frac * 0.6)
            }

            // Icon glyph at the low end of the track.
            Text {
                text: root.icon
                font.family: root.theme.iconFont
                font.pixelSize: 16
                anchors.left: root.orientation === Qt.Horizontal ? parent.left : undefined
                anchors.verticalCenter: root.orientation === Qt.Horizontal ? parent.verticalCenter : undefined
                anchors.leftMargin: root.orientation === Qt.Horizontal ? 14 : 0
                anchors.bottom: root.orientation === Qt.Vertical ? parent.bottom : undefined
                anchors.horizontalCenter: root.orientation === Qt.Vertical ? parent.horizontalCenter : undefined
                anchors.bottomMargin: root.orientation === Qt.Vertical ? 12 : 0
                color: root.frac > 0.15 ? root.theme.textOnAccent : root.theme.textSecondary
                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
                scale: slider.hovered || slider.pressed ? 1.25 : 1.0
                Behavior on scale {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutBack
                    }
                }
            }
        }
        handle: Item {
            width: 0
            height: 0
        }
    }
}
