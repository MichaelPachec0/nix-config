import QtQuick
import QtQuick.Layouts
import "../lib" as Lib

// Bar-center mode indicator: the active Hyprland submap's icon + label, hidden in
// the default map. Hover opens a key-hints popup (hover-persist + hide-bridge, per
// the bar idiom). Sits in rightRow and rides the layout; svc may be null-guarded.
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
        pulseColor: root.theme.accent
        // 4300 is Pill's default, tuned for an ambient weather alert. A "you are
        // in a mode" signal wants a faster cadence.
        pulseGapMs: 1200
        // Pulse only while this bar is actually on screen. An animation left
        // running in a hidden layer surface still paints at the monitor refresh
        // rate (112 fps measured on a hidden 120 Hz bar), and desktop/
        // ModeOverlay.qml carries the signal while the bar is covered. The two
        // conditions are complements, so exactly one of them ever animates.
        pulseActive: root.barWindow ? root.barWindow.surfaceVisible : false

        Lib.ModeBadge {
            theme: root.theme
            svc: root.svc
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
    }
    Lib.HoverBridge {
        id: bridge
        popup: popup
        widgetHovered: hov.hovered
    }
    // Close the popup if the submap ends while it is open -- no grace period,
    // the thing it describes is already gone.
    onVisibleChanged: if (!root.visible) bridge.hideNow()
}
