import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Toast popup overlay: a layer-shell surface pinned top-right, just below the
// bar, that stacks transient notification toasts (NotifService.toasts). Sized to
// its content and hidden when empty, so it never blocks clicks elsewhere. Does
// not take keyboard focus.
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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Hidden (no surface) when there are no toasts -> never intercepts clicks.
    visible: overlay.notif && overlay.notif.toasts.length > 0

    ColumnLayout {
        id: col
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        spacing: 8

        Repeater {
            model: overlay.notif ? overlay.notif.toasts : []
            ToastItem {
                required property var modelData
                Layout.fillWidth: true
                theme: overlay.theme
                notif: overlay.notif
                notification: modelData
            }
        }
    }
}
