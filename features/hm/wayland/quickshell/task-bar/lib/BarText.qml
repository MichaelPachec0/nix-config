import QtQuick

// Bar-text drop-in for every on-bar label/glyph (used inside a Lib.Pill; card /
// popup text stays a plain Text). Carries the per-glyph legibility treatment
// INLINE via Text.style -- no offscreen pass -- so the Pill no longer needs a
// second layer+MultiEffect shadow over its content:
//   ghost / ghost-glass -> full-black Text.Outline halo for reading over raw
//                          wallpaper.
//   frosted             -> Text.Raised directional depth on the glass fill.
// Inherits every Text property; reads BarStyle directly so callers don't thread
// a style prop to each glyph.
Text {
    style: BarStyle.current === "frosted" ? Text.Raised : Text.Outline
    styleColor: Qt.rgba(0, 0, 0, 1)
}
