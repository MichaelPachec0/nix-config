import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../hub" as Hub

// Toast popup overlay: a layer-shell surface pinned top-right, just below the
// bar, that stacks transient notification toasts grouped by app (NotifGroup in
// toastMode). Sized to its content and hidden when empty, so it never blocks
// clicks elsewhere. Hovering pauses the auto-dismiss sweep; leaving restarts the
// countdowns. Takes keyboard focus only on demand, so an inline-reply field in a
// toast is typeable when clicked without otherwise stealing focus.
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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

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
