import QtQuick

// Reusable mini line graph for 0..100 percentage histories. Pass a `values`
// array (newest last) and a `color`. Hover to TRACE: a vertical guide + a dot
// snap to the nearest sample and a small label shows that sample's value
// (`formatValue`, default "N%"). Used by the CPU/RAM/GPU section widgets.
Item {
    id: root

    property var values: []
    property color color: "white"
    property var formatValue: function (v) {
        return Math.round(v) + "%";
    }

    implicitWidth: 48
    implicitHeight: 22

    property int traceIdx: -1 // hovered sample index, -1 = none

    function _xOf(i) {
        return root.values.length < 2 ? 0 : i / (root.values.length - 1) * canvas.width;
    }
    function _yOf(v) {
        return canvas.height * (1 - Math.max(0, Math.min(100, v)) / 100);
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
            // trace marker
            if (root.traceIdx >= 0 && root.traceIdx < vals.length) {
                var tx = root._xOf(root.traceIdx), ty = root._yOf(vals[root.traceIdx]);
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.35);
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(tx, 0);
                ctx.lineTo(tx, height);
                ctx.stroke();
                ctx.fillStyle = root.color.toString();
                ctx.beginPath();
                ctx.arc(tx, ty, 2.2, 0, 2 * Math.PI);
                ctx.fill();
            }
        }
        Connections {
            target: root
            function onValuesChanged() { canvas.requestPaint(); }
            function onTraceIdxChanged() { canvas.requestPaint(); }
            function onColorChanged() { canvas.requestPaint(); }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: function (m) {
            if (root.values.length < 2) {
                root.traceIdx = -1;
                return;
            }
            var i = Math.round(m.x / Math.max(1, width) * (root.values.length - 1));
            root.traceIdx = Math.max(0, Math.min(root.values.length - 1, i));
        }
        onExited: root.traceIdx = -1
    }

    // Value label that follows the traced sample.
    Rectangle {
        visible: root.traceIdx >= 0 && root.traceIdx < root.values.length
        x: Math.max(0, Math.min(root.width - width, root._xOf(root.traceIdx) - width / 2))
        y: 0
        implicitWidth: lbl.implicitWidth + 6
        implicitHeight: lbl.implicitHeight + 2
        radius: 2
        color: Qt.rgba(0, 0, 0, 0.78)
        Text {
            id: lbl
            anchors.centerIn: parent
            text: (root.traceIdx >= 0 && root.traceIdx < root.values.length) ? root.formatValue(root.values[root.traceIdx]) : ""
            color: "white"
            font.family: "monospace"
            font.pixelSize: 9
        }
    }
}
