import QtQuick

// Reusable mini line graph for 0..100 percentage histories. Pass a `values`
// array (newest last) and a `color`. Hover to TRACE: a vertical guide, a dot
// that rides the line at the cursor's x, and a small label pinned to the dot
// showing the value there (`formatValue`, default "N%"). Dot and label
// interpolate along the drawn segments, so both glide with the cursor.
// Used by the CPU/RAM/GPU section widgets.
Item {
    id: root

    property var values: []
    property color color: "white"
    property var formatValue: function (v) {
        return Math.round(v) + "%";
    }

    implicitWidth: 48
    implicitHeight: 22

    // Cursor x within the canvas while hovering, -1 = not hovering.
    property real traceX: -1
    readonly property bool tracing: root.traceX >= 0 && root.values.length >= 2
    // Value on the line directly under the cursor, linearly interpolated between
    // the two bracketing samples so it lands exactly on the drawn segment.
    readonly property real traceVal: root.tracing ? root._valueAt(root.traceX) : 0

    function _xOf(i) {
        return root.values.length < 2 ? 0 : i / (root.values.length - 1) * canvas.width;
    }
    function _yOf(v) {
        return canvas.height * (1 - Math.max(0, Math.min(100, v)) / 100);
    }
    function _valueAt(px) {
        var n = root.values.length;
        if (n === 0)
            return 0;
        if (n === 1)
            return root.values[0];
        var pos = Math.max(0, Math.min(1, px / Math.max(1, canvas.width))) * (n - 1);
        var i0 = Math.floor(pos), i1 = Math.min(n - 1, i0 + 1), f = pos - i0;
        return root.values[i0] * (1 - f) + root.values[i1] * f;
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var vals = root.values;
            if (vals.length < 2)
                return;
            ctx.lineWidth = 1.5;
            ctx.strokeStyle = root.color.toString();
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.beginPath();
            for (var i = 0; i < vals.length; i++) {
                var x = root._xOf(i), y = root._yOf(vals[i]);
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.stroke();
            // Trace marker: vertical guide + dot riding the line at the cursor x.
            if (root.tracing) {
                var tx = Math.max(0, Math.min(width, root.traceX));
                var ty = root._yOf(root.traceVal);
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.35);
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(tx, 0);
                ctx.lineTo(tx, height);
                ctx.stroke();
                ctx.fillStyle = root.color.toString();
                ctx.beginPath();
                ctx.arc(tx, ty, 2.4, 0, 2 * Math.PI);
                ctx.fill();
            }
        }
        Connections {
            target: root
            function onValuesChanged() { canvas.requestPaint(); }
            function onTraceXChanged() { canvas.requestPaint(); }
            function onColorChanged() { canvas.requestPaint(); }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: function (m) {
            root.traceX = (root.values.length < 2) ? -1
                : Math.max(0, Math.min(width, m.x));
        }
        onExited: root.traceX = -1
    }

    // Value label pinned to the dot: tracks the cursor x and the line's y, sitting
    // just above the dot (flips below when the dot is near the top edge).
    Rectangle {
        id: tag
        visible: root.tracing
        readonly property real dotX: Math.max(0, Math.min(root.width, root.traceX))
        readonly property real dotY: root._yOf(root.traceVal)
        implicitWidth: lbl.implicitWidth + 6
        implicitHeight: lbl.implicitHeight + 2
        x: Math.max(0, Math.min(root.width - width, dotX - width / 2))
        y: {
            var above = dotY - height - 3;
            return above >= 0 ? above : Math.min(root.height - height, dotY + 4);
        }
        radius: 2
        color: Qt.rgba(0, 0, 0, 0.78)
        Text {
            id: lbl
            anchors.centerIn: parent
            text: root.tracing ? root.formatValue(root.traceVal) : ""
            color: "white"
            font.family: "monospace"
            font.pixelSize: 9
        }
    }
}
