import QtQuick

Item {
    id: root
    required property var theme
    property string text: ""
    property Item target: null

    readonly property int tailSize: 8
    readonly property int bodyWidth: 220

    implicitWidth: root.bodyWidth
    implicitHeight: body.height + root.tailSize
    width: implicitWidth
    height: implicitHeight

    // Positions itself directly above `target`, tail pointing down at its
    // top-center, tracking target's own geometry (it is typically a field
    // being validated, so it can move or resize under the balloon).
    function _reposition() {
        if (!root.target || !root.parent) return;
        var p = root.target.mapToItem(root.parent, root.target.width / 2, 0);
        root.x = p.x - root.width / 2;
        root.y = p.y - root.height;
    }

    Connections {
        target: root.target
        enabled: root.target !== null
        function onXChanged() { root._reposition(); }
        function onYChanged() { root._reposition(); }
        function onWidthChanged() { root._reposition(); }
        function onHeightChanged() { root._reposition(); }
    }
    onTargetChanged: root._reposition()
    Component.onCompleted: root._reposition()

    Rectangle {
        id: body
        x: 0
        y: 0
        width: root.bodyWidth
        height: msg.implicitHeight + theme.dialogPad * 2
        radius: theme.radius
        color: theme.face
        border.width: 1
        border.color: theme.faceDark

        Text {
            id: msg
            anchors.centerIn: parent
            width: parent.width - theme.dialogPad * 2
            text: root.text
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: theme.infoText
            font.family: theme.ui
            font.pixelSize: theme.uiSize
        }
    }

    // The tail has no Marlett equivalent at all (it is a filled triangle at
    // an arbitrary width/height ratio, not one of the font's fixed marks),
    // so it is drawn directly rather than guessed at as a codepoint -- the
    // same fallback the brief calls for when a glyph is absent.
    Canvas {
        id: tail
        width: root.tailSize * 2
        height: root.tailSize
        anchors.top: body.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        property color fillColor: theme.face
        property color strokeColor: theme.faceDark
        onFillColorChanged: requestPaint()
        onStrokeColorChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = tail.fillColor;
            ctx.strokeStyle = tail.strokeColor;
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(width, 0);
            ctx.lineTo(width / 2, height);
            ctx.closePath();
            ctx.fill();
            ctx.stroke();
        }
    }
}
