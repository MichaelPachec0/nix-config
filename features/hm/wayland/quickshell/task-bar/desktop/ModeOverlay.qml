import QtQuick
import Quickshell
import Quickshell.Wayland
import "../lib" as Lib

// Fullscreen-proof submap indicator. The bar is a WlrLayer.Top surface, so a
// fullscreen window covers it and Taskbar.surfaceVisible gates it off, taking
// the only signal that a submap is active away with it. That is not cosmetic:
// a submap without a catchall bind does not swallow typing, so a stuck one
// presents as "the keyboard is wedged" with nothing on screen naming the cause.
// This is the same badge on the Overlay layer, which Hyprland paints above
// fullscreen windows.
//
// Deliberately NOT desktop/ModePill.qml. That carries a ModePopup plus a
// HoverBridge for hover key hints, and the empty input region below means this
// surface receives no pointer events at all, so the popup could never open.
PanelWindow {
    id: root

    required property QtObject theme
    // NB: this must NOT be named submapSvc. Across the Variants delegate in
    // shell.qml an object's own property shadows an enclosing id, so
    // `submapSvc: submapSvc` would resolve to this component's own null
    // property. Same trap as netSvc, routerSvc and powerzStats.
    required property var svc
    // True while a fullscreen window covers THIS monitor's bar.
    required property bool covered
    // True while the session lock owns the screen.
    required property bool locked
    // Bound to the bar's own height rather than restating it, so the two cannot
    // drift apart.
    required property int barHeight

    visible: root.svc && root.svc.current !== "" && root.covered && !root.locked

    // Full width like Taskbar, with the pill centred inside, rather than
    // anchoring only the top edge and letting layer-shell centre the surface.
    // The single-edge form is what the protocol specifies, but no PanelWindow in
    // this tree anchors fewer than two edges, and the empty input region below
    // makes the extra width free of input cost. This also puts the pill on the
    // same axis as the bar's own centerRow.
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: root.barHeight
    color: "transparent"

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:mode"
    // Click-through. Without an empty input region this eats every click in the
    // top centre of a fullscreen game.
    mask: Region {}
    // Never take keys, least of all while a submap is active.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Lib.Pill {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        theme: root.theme
        ringColor: root.theme.accent
        pulseColor: root.theme.accent
        pulseGapMs: 1200
        // Complement of ModePill's gate: this surface only exists while the bar
        // is covered, so only one of the two ever animates.
        pulseActive: root.visible

        Lib.ModeBadge {
            theme: root.theme
            svc: root.svc
        }
    }
}
