import QtQuick

// Compact themed horizontal slider. Drag updates `value` and emits `moved(v)`
// continuously; `committed(v)` fires on release. Consumers keep the knob synced
// to live data with `Binding on value { when: !dragging; value: ... }` so an
// in-progress drag is never fought by an incoming update. Shared by the audio
// popups (the Bluetooth widget keeps its own inline copy).
Item {
    id: sl
    required property QtObject theme
    property real from: 0
    property real to: 100
    property real value: 0
    property bool snap: true
    property bool dragging: false
    signal committed(real v)
    signal moved(real v)

    implicitHeight: 16

    // Common track for the fill AND the knob so they can never disagree: the knob
    // is 12px wide, so its centre travels [6, width-6] as its left edge (_knobX)
    // goes [0, width-12]. The fill reaches the knob CENTRE (_knobX + 6). `_span`
    // guards a zero-width range (to == from) that would divide to NaN/Infinity.
    readonly property real _span: Math.max(1e-6, sl.to - sl.from)
    readonly property real _frac: Math.max(0, Math.min(1, (sl.value - sl.from) / sl._span))
    readonly property real _knobRange: Math.max(0, sl.width - 12)
    readonly property real _knobX: sl._frac * sl._knobRange

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        height: 4
        radius: 2
        color: sl.theme.bgItem
    }
    // Filled portion (only for 0-based ranges; bipolar ranges stay un-filled).
    Rectangle {
        visible: sl.from >= 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        height: 4
        radius: 2
        width: sl._knobX + 6   // reach the knob centre, so fill + knob stay aligned
        color: sl.theme.accent
    }
    // Center tick for bipolar ranges (e.g. balance).
    Rectangle {
        visible: sl.from < 0
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: 8
        radius: 1
        color: sl.theme.textSecondary
        x: (0 - sl.from) / sl._span * sl._knobRange + 5
    }
    Rectangle {
        width: 12
        height: 12
        radius: 6
        anchors.verticalCenter: parent.verticalCenter
        color: sl.theme.accent
        x: sl._knobX
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function apply(mx) {
            var t = Math.max(0, Math.min(1, (mx - 6) / Math.max(1e-6, sl._knobRange)));
            var v = sl.from + t * (sl.to - sl.from);
            sl.value = sl.snap ? Math.round(v) : v;
            sl.moved(sl.value);
        }
        onPressed: {
            sl.dragging = true;
            apply(mouseX);
        }
        onPositionChanged: if (pressed)
            apply(mouseX)
        onReleased: {
            sl.dragging = false;
            sl.committed(sl.value);
        }
    }
}
