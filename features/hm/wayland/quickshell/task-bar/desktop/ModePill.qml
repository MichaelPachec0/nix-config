import QtQuick
import QtQuick.Layouts
import "../lib" as Lib

// Bar-center mode indicator: the active Hyprland submap's icon + label, hidden in
// the default map. Hover opens a key-hints popup (hover-persist + hide-bridge, per
// the bar idiom). Sits in centerRow and rides the layout; svc may be null-guarded.
// Uses Lib.Pill so it shares the other clusters' floating layer (glass fill, drop
// shadow, width spring, BarStyle) -- distinguished by an accent ring + accent text.
Item {
    id: root
    required property QtObject theme
    required property var svc
    required property var barWindow

    visible: root.svc && root.svc.current !== ""
    implicitWidth: root.visible ? pill.implicitWidth : 0
    implicitHeight: 30

    Lib.Pill {
        id: pill
        anchors.centerIn: parent
        theme: root.theme
        ringColor: root.theme.accent
        gap: 6

        Lib.BarText {
            Layout.alignment: Qt.AlignVCenter
            visible: root.svc && root.svc.iconCp() !== ""
            text: (root.svc && root.svc.iconCp() !== "")
                ? String.fromCharCode(parseInt(root.svc.iconCp(), 16)) : ""
            font.family: root.theme.faFont
            font.pixelSize: 12
            color: root.theme.accent
        }
        Lib.BarText {
            Layout.alignment: Qt.AlignVCenter
            text: root.svc ? root.svc.label() : ""
            font.family: root.theme.iconFont
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: root.theme.accent
        }
    }

    ModePopup {
        id: popup
        theme: root.theme
        barWindow: root.barWindow
        anchorItem: root
        svc: root.svc
    }
    HoverHandler {
        id: hov
        onHoveredChanged: hov.hovered ? popup.show() : hideTimer.restart()
    }
    Timer {
        id: hideTimer
        interval: 250
        onTriggered: if (!hov.hovered && !popup.contentHovered) popup.hide()
    }
    // Hide-bridge: leaving the popup surface directly must also re-arm the timer.
    Connections {
        target: popup
        function onContentHoveredChanged() {
            if (!popup.contentHovered && !hov.hovered) hideTimer.restart();
        }
    }
    // Close the popup if the submap ends while it is open.
    onVisibleChanged: if (!root.visible) popup.hide()
}
