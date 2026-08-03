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

    // Extra drop under the glyphs, in px, on top of Text.Raised.
    //
    // Text.Raised is a FIXED 1px down-right shadow -- Qt exposes no offset for
    // it, and styleColor is already opaque black, so there is no knob to make it
    // read deeper. This draws a second copy of the glyphs further down-right,
    // giving a two-step falloff (1px hard from Text.Raised, then this) which is
    // what sells the lift.
    //
    // Deliberately a sibling glyph node rather than a layer+MultiEffect drop
    // shadow: an offscreen pass here would re-rasterise and re-blur on every
    // change, which is exactly the cost just removed from Pill. A duplicate Text
    // is a plain extra draw with no render-target switch, and glyph rasterisation
    // is cached per (font, glyph) so the second copy reuses the first's atlas.
    // Defaults come from BarStyle so hand-drawn glyphs elsewhere (the router's
    // signal bars) sit on the same depth plane; override per call site if needed.
    property int lift: BarStyle.glyphLift
    property real liftAlpha: BarStyle.glyphLiftAlpha

    // A child with NEGATIVE z draws behind its parent's own content, which is
    // what lets this sit under the glyphs while still inheriting from them.
    Text {
        z: -1
        visible: BarStyle.current === "frosted" && barText.lift > 0
        x: 1
        y: barText.lift
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
