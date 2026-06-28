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
        width: Math.max(0, Math.min(sl.width, (sl.value - sl.from) / (sl.to - sl.from) * sl.width))
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
        x: (0 - sl.from) / (sl.to - sl.from) * (sl.width - 12) + 5
    }
    Rectangle {
        width: 12
        height: 12
        radius: 6
        anchors.verticalCenter: parent.verticalCenter
        color: sl.theme.accent
        x: Math.max(0, Math.min(sl.width - 12, (sl.value - sl.from) / (sl.to - sl.from) * (sl.width - 12)))
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function apply(mx) {
            var t = Math.max(0, Math.min(1, (mx - 6) / (sl.width - 12)));
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
