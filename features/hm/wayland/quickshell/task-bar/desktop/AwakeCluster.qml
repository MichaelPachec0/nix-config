import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "../lib" as Lib

// Single content item of the "awake" pill. Owns the shared InhibitService, the
// two thin icon widgets, the window-bound Wayland idle inhibitor, and the shared
// hover popup. Hovering anywhere on the cluster opens the popup (RouterPopup
// hide-bridge so the pointer can travel into it); clicking an icon quick-toggles
// its concern.
RowLayout {
    id: cluster

    required property QtObject theme
    required property var barWindow

    spacing: 8

    Lib.InhibitService {
        id: svc
    }

    // Wayland idle-inhibit for the "idle" concern (needs the bar surface).
    IdleInhibitor {
        window: cluster.barWindow
        enabled: svc.idleOn
    }

    InhibitWidget {
        Layout.alignment: Qt.AlignVCenter
        theme: cluster.theme
        barWindow: cluster.barWindow
        svc: svc
    }
    SleepInhibitWidget {
        Layout.alignment: Qt.AlignVCenter
        theme: cluster.theme
        barWindow: cluster.barWindow
        svc: svc
    }

    HoverHandler {
        id: clusterHover
        onHoveredChanged: clusterHover.hovered ? popup.show() : hideTimer.restart()
    }
    Timer {
        id: hideTimer
        interval: 250
        onTriggered: if (!clusterHover.hovered && !popup.contentHovered)
            popup.hide()
    }
    Connections {
        target: popup
        function onContentHoveredChanged() {
            if (!popup.contentHovered && !clusterHover.hovered)
                hideTimer.restart();
        }
    }
    InhibitPopup {
        id: popup
        theme: cluster.theme
        barWindow: cluster.barWindow
        anchorItem: cluster
        svc: svc
    }
}
