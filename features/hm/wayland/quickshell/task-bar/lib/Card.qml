import QtQuick
import QtQuick.Layouts

// Base hub card: a themed rounded surface with a soft shadow and a subtle
// hover lift/border. Children go into the default ColumnLayout. Adapted from
// surface-dots (dark-only here; the light-mode border branch is dropped).
Rectangle {
    id: root

    required property QtObject theme
    property int pad: theme.padCard

    default property alias content: container.data

    color: theme.bgCard
    radius: theme.radiusOuter

    implicitHeight: container.implicitHeight + (root.pad * 2)
    implicitWidth: container.implicitWidth + (root.pad * 2)

    HoverHandler {
        id: hoverHandler
    }
    scale: hoverHandler.hovered ? 1.017 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutQuint
        }
    }

    border.width: 1
    border.color: hoverHandler.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.05)
    Behavior on border.color {
        ColorAnimation {
            duration: 200
        }
    }

    // Soft drop shadow behind the card.
    Rectangle {
        z: -1
        anchors.fill: parent
        color: "black"
        opacity: 0.22
        radius: parent.radius
    }

    ColumnLayout {
        id: container
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: 0
    }
}
