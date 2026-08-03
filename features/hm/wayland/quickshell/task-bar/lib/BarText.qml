import QtQuick

// Bar-text drop-in for every on-bar label/glyph (used inside a Lib.Pill; card /
// popup text stays a plain Text). Carries the per-glyph legibility treatment
// INLINE via Text.style -- no offscreen pass -- so the Pill no longer needs a
// second layer+MultiEffect shadow over its content:
//   ghost / ghost-glass -> full-black Text.Outline halo for reading over raw
//                          wallpaper.
//   frosted             -> Text.Raised directional depth on the glass fill,
//                          deepened by `lift` below.
// Inherits every Text property; reads BarStyle directly so callers don't thread
// a style prop to each glyph.
Text {
    id: barText

    style: BarStyle.current === "frosted" ? Text.Raised : Text.Outline
    styleColor: Qt.rgba(0, 0, 0, 1)

    // Extruded body under the glyphs: one copy per pixel step along the lift
    // vector, so the face sits on a SOLID slab.
    //
    // Text.Raised is a FIXED 1px down-right shadow -- Qt exposes no offset for
    // it, and styleColor is already opaque black, so there is no knob to make it
    // read deeper. A single offset copy deepens it but reads as a detached
    // second image, because nothing occupies the gap between the glyph and its
    // shadow. Stepping one copy per pixel fills that gap, which is what turns a
    // drop shadow into extrusion.
    //
    // Deliberately sibling glyph nodes rather than a layer+MultiEffect drop
    // shadow: an offscreen pass here would re-rasterise and re-blur on every
    // change, which is exactly the cost just removed from Pill. Duplicate Texts
    // are plain extra draws with no render-target switch, and glyph
    // rasterisation is cached per (font, glyph) so every copy reuses the face's
    // atlas entry.
    //
    // Defaults come from BarStyle so hand-drawn glyphs elsewhere (the router's
    // signal bars) sit on the same depth plane; override per call site if needed.
    property int lift: BarStyle.glyphLift
    property int liftX: BarStyle.glyphLiftX
    property real liftAlpha: BarStyle.glyphLiftAlpha

    // Children with NEGATIVE z draw behind their parent's own content, which is
    // what lets these sit under the glyphs while still inheriting from them.
    // Among equal-z siblings the draw order is creation order, so index 0 must
    // be the DEEPEST step: it is created first and everything stacks on top.
    Repeater {
        model: BarStyle.glyphLifted ? barText.lift : 0
        delegate: Text {
            required property int index
            readonly property int step: barText.lift - index

            z: -1
            x: Math.round(step * barText.liftX / barText.lift)
            y: step
            width: barText.width
            height: barText.height
            text: barText.text
            font: barText.font
            elide: barText.elide
            horizontalAlignment: barText.horizontalAlignment
            verticalAlignment: barText.verticalAlignment
            color: Qt.rgba(0, 0, 0, barText.liftAlpha)
        }
    }

    // Soft halo behind the extrusion, as copies nudged out in all eight
    // directions from the body's midpoint.
    //
    // Two rejected approaches, both worth not repeating:
    //   Text.Outline -- a crisp 1px rim. Reads as a wireframe traced around the
    //     shadow at zoom and as nothing at 1:1; raising alpha only sharpens the
    //     wireframe.
    //   one scaled-up copy -- scaling happens about the item's BOX centre, and
    //     the box is wider than the glyphs whenever a caller sets an explicit
    //     width (the window title). Glyphs left of that centre get pushed
    //     further left, so the halo drifted up and to the left of the text.
    //
    // Eight offsets around a centre are symmetric by construction, so the halo
    // cannot drift regardless of alignment or box width. Still no offscreen blur
    // pass; each copy is a plain draw reusing the face's glyph-atlas entries.
    readonly property var glowOffsets: [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, -1], [-1, 1], [1, 1]]

    Repeater {
        model: (BarStyle.glyphLifted && BarStyle.glyphGlowAlpha > 0) ? barText.glowOffsets.length : 0
        delegate: Text {
            required property int index
            // Centred on the MIDDLE of the extrusion, not its deepest step, so
            // the glow wraps the whole body evenly instead of pooling at one end.
            z: -2
            x: Math.round(barText.liftX / 2) + BarStyle.glyphGlowOffsetX + barText.glowOffsets[index][0] * BarStyle.glyphGlowSpread
            y: Math.round(barText.lift / 2) + barText.glowOffsets[index][1] * BarStyle.glyphGlowSpread
            width: barText.width
            height: barText.height
            text: barText.text
            font: barText.font
            elide: barText.elide
            horizontalAlignment: barText.horizontalAlignment
            verticalAlignment: barText.verticalAlignment
            color: Qt.rgba(BarStyle.glyphGlowColor.r, BarStyle.glyphGlowColor.g, BarStyle.glyphGlowColor.b, BarStyle.glyphGlowAlpha)
        }
    }
}
