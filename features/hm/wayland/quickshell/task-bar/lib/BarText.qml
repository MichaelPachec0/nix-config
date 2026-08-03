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

    // Soft halo behind the whole extrusion.
    //
    // Text.Outline was the cheap first attempt and is the wrong shape: it is a
    // crisp 1px rim, which reads as a wireframe around the shadow at zoom and as
    // nothing at all at 1:1. Scaling a single low-alpha copy up instead gives a
    // genuine soft edge, because the glyphs are resampled rather than outlined --
    // still one extra draw, still no offscreen blur pass.
    Text {
        z: -2 // behind every extrusion step
        visible: BarStyle.glyphLifted && BarStyle.glyphGlowAlpha > 0
        x: barText.liftX
        y: barText.lift
        width: barText.width
        height: barText.height
        text: barText.text
        font: barText.font
        elide: barText.elide
        horizontalAlignment: barText.horizontalAlignment
        verticalAlignment: barText.verticalAlignment
        transformOrigin: Item.Center
        scale: 1.0 + BarStyle.glyphGlowSpread
        color: Qt.rgba(BarStyle.glyphGlowColor.r, BarStyle.glyphGlowColor.g, BarStyle.glyphGlowColor.b, BarStyle.glyphGlowAlpha)
    }
}
