import QtQuick
import QtQuick.Layouts

// Bar audio widget: volume glyph + percentage. Left-click opens the mixer
// dropdown, middle-click toggles mute, scroll adjusts master volume. Backed by
// the shared AudioService (native PipeWire). Mirrors WifiWidget/BluetoothWidget.
// The interactive hover mini (AudioInfoPopup) is wired in a later task.
Item {
    id: root

    required property QtObject theme
    required property var barWindow
    required property var audio // Lib.AudioService

    implicitWidth: row.implicitWidth
    implicitHeight: 24

    function label() {
        if (!root.audio || !root.audio.ready)
            return "No audio";
        if (root.audio.muted)
            return "Muted";
        return root.audio.volume + "%";
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 5
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.audio ? root.audio.volumeGlyph(root.audio.volume, root.audio.muted) : ""
            font.family: root.theme.iconFont
            font.pixelSize: 14
            color: (root.audio && root.audio.muted) ? root.theme.textSecondary : root.theme.accent
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.label()
            font.family: root.theme.textFont
            font.pixelSize: 11
            color: root.theme.textSecondary
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton) {
                if (root.audio)
                    root.audio.toggleMute();
                return;
            }
            info.iconHovered = false;
            info.hide();
            popup.toggle();
        }
        onWheel: function (wheel) {
            if (root.audio)
                root.audio.stepVolume(wheel.angleDelta.y > 0 ? 2 : -2);
        }
        onContainsMouseChanged: {
            if (containsMouse && !popup.visible) {
                info.iconHovered = true;
                info.show();
            } else {
                info.iconHovered = false;
            }
        }
    }

    AudioPopup {
        id: popup
        theme: root.theme
        anchorItem: root
        barWindow: root.barWindow
        audio: root.audio
    }
    AudioInfoPopup {
        id: info
        theme: root.theme
        anchorItem: root
        barWindow: root.barWindow
        audio: root.audio
    }
}
