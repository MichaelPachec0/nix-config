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

    // True when both concerns are on with the same expiry: the two icons then
    // share a single timer (pushed right of both) instead of one timer each.
    // Lock produces an identical expiry, so a locked pair always consolidates.
    readonly property bool consolidated: svc.idleOn && svc.sleepOn
        && svc.idleExpiry === svc.sleepExpiry

    spacing: 8

    Lib.InhibitService {
        id: svc
    }

    // Wayland idle-inhibit for the "idle" concern (needs the bar surface).
    IdleInhibitor {
        window: cluster.barWindow
        enabled: svc.idleOn
    }

    // Idle icon, then sleep icon, each with a countdown slot. The per-icon slots
    // hide and a single shared slot (after both icons) shows when consolidated;
    // otherwise each on-concern shows its own timer, so cancelling one leaves the
    // timer beside the still-inhibited icon.
    InhibitWidget {
        Layout.alignment: Qt.AlignVCenter
        theme: cluster.theme
        svc: svc
    }
    AwakeTimerSlot {
        Layout.alignment: Qt.AlignVCenter
        visible: svc.idleOn && !cluster.consolidated
        theme: cluster.theme
        label: svc.countdownText("idle")
    }
    SleepInhibitWidget {
        Layout.alignment: Qt.AlignVCenter
        theme: cluster.theme
        svc: svc
    }
    AwakeTimerSlot {
        Layout.alignment: Qt.AlignVCenter
        visible: svc.sleepOn && !cluster.consolidated
        theme: cluster.theme
        label: svc.countdownText("sleep")
    }
    AwakeTimerSlot {
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: 2
        visible: cluster.consolidated
        theme: cluster.theme
        label: svc.countdownText("idle") // both equal when consolidated
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
