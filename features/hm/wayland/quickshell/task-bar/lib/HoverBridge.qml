import QtQuick

// Keeps a bar popup alive while the cursor is over the WIDGET or over the POPUP,
// and closes it a beat after it leaves both.
//
// Two idioms had grown for this. The good one folds the popup's own hover into a
// single `over` predicate. The fragile one is three separate pieces -- a hover
// handler that shows, a hide Timer, and a `Connections` that re-arms that timer
// when the cursor leaves the POPUP surface directly instead of travelling back
// across the widget. That third piece is the one that keeps getting dropped, and
// without it the popup hangs open until something else hides it.
//
// This is the first idiom, extracted. The failure mode goes away by
// construction: there is one signal, and it already accounts for both surfaces,
// so there is no separate bridge left to forget.
//
// Usage: hand it the popup and point widgetHovered at whatever the widget
// already has (a HoverHandler's `hovered`, a MouseArea's `containsMouse`).
//
//   Lib.HoverBridge {
//       popup: pop
//       widgetHovered: hov.hovered
//   }
//
// The popup must expose show(), hide() and contentHovered -- i.e. be a
// Lib.BasePopup.
QtObject {
    id: bridge

    required property var popup
    // Bind to the widget's own hover source.
    property bool widgetHovered: false
    // Grace period after leaving both surfaces. Bridges the few pixels of gap
    // between the bar item and the popup below it.
    property int delay: 250

    // Emitted alongside the show/hide, for the callers that gate a poll on the
    // popup being up (SysPopup drives SysStats.wantDetail this way).
    signal opened
    signal closed

    readonly property bool over: bridge.widgetHovered || (bridge.popup ? bridge.popup.contentHovered : false)

    onOverChanged: {
        if (bridge.over) {
            bridge.hideTimer.stop();
            bridge.popup.show();
            bridge.opened();
        } else {
            bridge.hideTimer.restart();
        }
    }

    // A property rather than a plain child: QtObject has no default property, and
    // QtObject (not Item) is what keeps this out of the widget's layout.
    property Timer hideTimer: Timer {
        interval: bridge.delay
        onTriggered: {
            if (bridge.over)
                return;
            bridge.popup.hide();
            bridge.closed();
        }
    }

    // Close immediately, skipping the grace period (the mode pill does this when
    // its submap ends out from under the popup).
    function hideNow() {
        bridge.hideTimer.stop();
        bridge.popup.hide();
        bridge.closed();
    }
}
