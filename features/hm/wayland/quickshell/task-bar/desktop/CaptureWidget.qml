import QtQuick
import "../lib" as Lib

// Privacy glyphs: camera / microphone / screencast, shown only while their
// signal is actually active so the bar stays quiet the rest of the time. Click
// opens DevicePopup, which names the devices and the apps using them.
//
// Its own widget rather than a section of MediaWidget: the two have unrelated
// lifetimes. Folding them together forced MediaWidget to stay visible with no
// MPRIS player just so these glyphs could render, which left a dead play icon
// and an empty player card reachable by hover whenever a device was hot without
// music playing.
Item {
    id: root

    required property QtObject theme
    required property var barWindow // the bar PanelWindow, for popup anchoring
    // Named `capture` while shell.qml's id is `captureSvc`: an own-property
    // shadows an enclosing-component id across the Variants delegate, so
    // matching names would silently bind this to its own null property.
    required property var capture
    required property var audio

    // cameraUnknown counts as active: a camera scan that could not answer must
    // stay visible and clickable rather than silently reading as "idle".
    readonly property bool captureActive: root.capture ? root.capture.anyActive : false

    visible: root.captureActive
    implicitWidth: root.captureActive ? glyphRow.implicitWidth : 0
    implicitHeight: 24

    Row {
        id: glyphRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        // The camera glyph is the one that renders while INACTIVE: when the
        // scan could not answer it takes the warning tint instead of hiding,
        // because hiding it would both make the popup unreachable and silently
        // assert the camera is idle.
        Lib.BarText {
            visible: root.capture && (root.capture.cameraActive || root.capture.cameraUnknown)
            text: String.fromCodePoint(0xF030)
            font.family: root.theme.iconFont
            font.pixelSize: 12
            color: (root.capture && root.capture.cameraUnknown) ? root.theme.accentYellow : root.theme.accentRed
        }
        Lib.BarText {
            visible: root.capture && root.capture.micActive
            text: String.fromCodePoint(0xF130)
            font.family: root.theme.iconFont
            font.pixelSize: 12
            color: root.theme.accentRed
        }
        Lib.BarText {
            visible: root.capture && root.capture.castActive
            text: String.fromCodePoint(0xF06E)
            font.family: root.theme.iconFont
            font.pixelSize: 12
            color: root.theme.accentRed
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: devicePopup.toggle()
    }

    DevicePopup {
        id: devicePopup
        theme: root.theme
        barWindow: root.barWindow
        anchorItem: root
        capture: root.capture
        audio: root.audio
    }

    // Close on lock. A grabFocus bar popup open when the session locks has
    // crashed Hyprland 0.56 (see the hypr-popup-lock-crash notes); the
    // compositor-side guard is a local patch, so do not rely on it alone.
    Connections {
        target: root.capture
        function onLockedChanged() {
            if (root.capture.locked)
                devicePopup.visible = false;
        }
    }
}
