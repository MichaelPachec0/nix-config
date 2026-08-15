import QtQuick
import Quickshell

// Shared base for every bar popup that hangs under the taskbar.
//
// Before this existed, each popup carried its own copy of the same four things:
// the transparent/hidden window setup, the Bottom|Right anchor, a `reclamp()`
// that wrote the same four `anchor.rect` fields, and `show()` / `hide()`. That
// block was duplicated verbatim in nine files and near-verbatim in six more,
// which is how they drifted -- some clamp the left edge to the bar, some don't.
//
// Deliberately a PURE refactor: `placeAt()` does NOT clamp. The popups that
// clamp today call `reclamp()` (which does); the ones that don't call
// `placeAt()` directly and keep behaving exactly as before. Folding the clamp
// into `placeAt()` would silently move the popups that currently run off the
// right edge -- worth fixing, but as its own change with its own verification.
PopupWindow {
    id: root

    required property QtObject theme
    required property var barWindow
    // The bar item the popup hangs under. Optional: the click-menus
    // (Audio/Bluetooth/Device) are positioned by an explicit x from their
    // widget instead, via placeAt().
    property var anchorItem: null

    // Set by subclasses to the popup card's own hover state. The widget-side
    // hide-bridge watches this so the cursor can travel into the popup without
    // it collapsing -- see Lib.HoverBridge.
    property bool contentHovered: false

    // Gap between the bar's bottom edge and the popup.
    property int gap: 4
    // Left/right screen margins used by the clamp.
    property int edgeMargin: 4
    property int rightMargin: 8

    color: "transparent"
    visible: false

    anchor.window: root.barWindow
    anchor.edges: Edges.Bottom
    // Pin the left edge and grow rightward: gravity without a horizontal
    // component centers the popup, which shifts it as its width changes.
    anchor.gravity: Edges.Bottom | Edges.Right

    // Keep a desired left edge inside the bar.
    function clampX(x) {
        return Math.max(root.edgeMargin, Math.min(x, root.barWindow.width - root.implicitWidth - root.rightMargin));
    }

    // Put the popup's left edge at `x` (bar-window coordinates), just under the
    // bar. Width/height are zeroed: the anchor rect is a point, not a region.
    function placeAt(x) {
        root.anchor.rect.x = x;
        root.anchor.rect.y = root.barWindow.height + root.gap;
        root.anchor.rect.width = 0;
        root.anchor.rect.height = 0;
    }

    // Align to the anchor item's left edge, clamped on-screen.
    function reclamp() {
        if (!root.anchorItem)
            return;
        root.placeAt(root.clampX(root.anchorItem.mapToItem(null, 0, 0).x));
    }

    // Center under the anchor item. NOT clamped -- the two tooltips that center
    // (BtInfoPopup, AudioInfoPopup) never clamped, and this stays a pure
    // refactor. They can run off the right edge; wrapping this in clampX() is
    // the fix, but it moves them, so it wants its own verification pass.
    function reclampCentered() {
        if (!root.anchorItem)
            return;
        var wc = root.anchorItem.mapToItem(null, root.anchorItem.width / 2, 0).x;
        root.placeAt(Math.round(wc - root.implicitWidth / 2));
    }

    function show() {
        if (root.visible)
            return;
        root.reclamp();
        root.visible = true;
    }
    function hide() {
        root.visible = false;
    }
}
