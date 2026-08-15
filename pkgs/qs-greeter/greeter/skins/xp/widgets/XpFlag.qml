import QtQuick

// The Windows flag mark for the banner.
//
// Drawn as vector geometry rather than shipped as an image, for two
// independent reasons. Practically: Marlett has no flag glyph (verified
// against its cmap in XpComboBox.qml), so there is no font codepoint to
// borrow, and a bitmap would need a fixed size while this skin is asked for
// everything from a 22px dialog mark to a banner mark. Legally: the actual
// XP artwork is Microsoft's, and extracting it out of luna.msstyles into a
// git repository is not something this skin does -- this is a recognizable
// recreation built from four brand-colored quadrants, the same approach the
// open-source XP CSS recreations take.
//
// The shape: four panes in a 2x2 grid, sheared to lean right, with each row
// riding a shallow wave and the right-hand column sitting higher than the
// left. The wave is what makes it read as a flag rather than as four
// rectangles; the shear is what stops it reading as a window.
Canvas {
    id: root
    required property var theme

    implicitWidth: 32
    implicitHeight: 28
    width: implicitWidth
    height: implicitHeight
    antialiasing: true

    // Repaint whenever anything the paint depends on moves. Canvas does not
    // track property reads the way a binding does, so every input needs an
    // explicit hook or the mark silently keeps its first frame.
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections {
        target: root.theme
        function onFlagRedChanged() { root.requestPaint(); }
        function onFlagGreenChanged() { root.requestPaint(); }
        function onFlagBlueChanged() { root.requestPaint(); }
        function onFlagYellowChanged() { root.requestPaint(); }
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);

        var w = width;
        var h = height;

        // How far the top edge leans right of the bottom edge, as a
        // fraction of width. Small: the flag leans, it does not topple.
        var shear = 0.16;
        // Vertical rise from the left edge to the right edge -- the flag is
        // held up on its right side.
        var rise = 0.13;
        // Depth of the wave running along each horizontal edge.
        var wave = 0.055;
        // Gap between panes, as a fraction of the full mark.
        var gap = 0.055;

        // Horizontal band edges (left column, then right column).
        var cols = [[0.0, 0.5 - gap / 2], [0.5 + gap / 2, 1.0]];
        // Vertical band edges (top row, then bottom row).
        var rows = [[0.0, 0.5 - gap / 2], [0.5 + gap / 2, 1.0]];

        var colors = [
            [root.theme.flagRed, root.theme.flagGreen],
            [root.theme.flagBlue, root.theme.flagYellow]
        ];

        // Maps a normalized (u, v) in the flag's own space onto the canvas,
        // applying the shear and the right-side rise. Everything below is
        // expressed in that space so the wave and the gaps stay proportional
        // at any size.
        function px(u, v) { return (u * (1.0 - shear) + shear * (1.0 - v)) * w; }
        function py(u, v) { return (v * (1.0 - rise) + (1.0 - u) * rise) * h; }

        // Vertical offset of the wave at horizontal position u. Half a
        // period across the mark: down through the middle, back up at the
        // right edge, which is the silhouette the real mark has.
        function waveAt(u) { return Math.sin(u * Math.PI) * wave * h; }

        // One pane, with both horizontal edges curved by waveAt() and both
        // vertical edges straight. Sampled rather than fitted to a bezier:
        // a handful of segments is indistinguishable at mark sizes and
        // keeps the wave definition in one place instead of in four control
        // points that have to be kept consistent with each other.
        function pane(u0, u1, v0, v1, color) {
            var steps = 12;
            var i;
            ctx.beginPath();
            for (i = 0; i <= steps; i++) {
                var u = u0 + (u1 - u0) * (i / steps);
                var x = px(u, v0);
                var y = py(u, v0) + waveAt(u);
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
            for (i = steps; i >= 0; i--) {
                var ub = u0 + (u1 - u0) * (i / steps);
                ctx.lineTo(px(ub, v1), py(ub, v1) + waveAt(ub));
            }
            ctx.closePath();
            ctx.fillStyle = color;
            ctx.fill();
        }

        for (var c = 0; c < 2; c++) {
            for (var r = 0; r < 2; r++) {
                pane(cols[c][0], cols[c][1], rows[r][0], rows[r][1], colors[r][c]);
            }
        }
    }
}
