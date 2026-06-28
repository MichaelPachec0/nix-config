import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../hub" as Hub

// Toast popup overlay: a layer-shell surface pinned top-right, just below the
// bar, that stacks transient notification toasts grouped by app (NotifGroup in
// toastMode). Sized to its content and hidden when empty, so it never blocks
// clicks elsewhere. Hovering pauses the auto-dismiss sweep; leaving restarts the
// countdowns. Keyboard focus is gated on hover: the surface stays unfocusable
// (WlrKeyboardFocus.None) so an arriving toast never steals focus from the
// active window, and only becomes focusable (OnDemand) while the cursor is over
// it -- enough to click into and type the inline-reply field. (Pointer events
// don't need keyboard focus, so dismiss/expand clicks work in either state.)
PanelWindow {
    id: overlay

    required property QtObject theme
    required property var notif // Lib.NotifService

    readonly property int barHeight: 40

    anchors {
        top: true
        right: true
    }
    margins {
        top: overlay.barHeight + 8
        right: 12
    }
    implicitWidth: 360
    implicitHeight: Math.max(1, col.implicitHeight)
    color: "transparent"

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-toasts"
    // None on arrival -> can't steal focus; OnDemand only while hovered so the
    // inline-reply field is clickable/typeable. (overlayHover is declared below;
    // QML resolves the id after the component is built.)
    WlrLayershell.keyboardFocus: overlayHover.hovered ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    visible: overlay.notif && overlay.notif.toasts.length > 0

    ColumnLayout {
        id: col
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        spacing: 8

        // Pause auto-dismiss while the cursor is over the toasts.
        HoverHandler {
            id: overlayHover
            onHoveredChanged: {
                overlay.notif.toastPaused = overlayHover.hovered;
                if (!overlayHover.hovered)
                    overlay.notif.refreshToastTimers();
            }
        }

        Repeater {
            model: overlay.notif ? overlay.notif.toastGroups : []
            Hub.NotifGroup {
                required property var modelData
                Layout.fillWidth: true
                theme: overlay.theme
                notif: overlay.notif
                entry: modelData
                toastMode: true
            }
        }
    }
}
