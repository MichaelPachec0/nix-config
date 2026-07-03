import QtQuick

// Bar-text drop-in for every on-bar label/glyph (used inside a Lib.Pill; card /
// popup text stays a plain Text). It can add a crisp Text.Outline for maximum
// legibility on any wallpaper, but the current looks lean on the Pill's tight
// per-glyph shadows instead, so the outline is off. To bring it back, gate
// `style` on BarStyle.current (e.g. === "ghost" ? Text.Outline : Text.Normal).
// Inherits every Text property; reads BarStyle directly so callers don't thread
// a style prop to each glyph.
Text {
    style: Text.Normal
    styleColor: Qt.rgba(0, 0, 0, 1)
}
