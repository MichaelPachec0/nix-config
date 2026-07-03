import QtQuick

// A Text that gains a crisp black outline in the ghost bar look, so light glyphs
// stay legible on ANY wallpaper (a blurred shadow spreads its darkness too thin
// to hold up on bright backgrounds; a 1px stroke concentrates it at the edge).
// In the frosted look the translucent fill carries legibility, so the outline is
// off. Drop-in for Text -- inherits every Text property; reads the BarStyle
// singleton directly so callers don't thread a style prop to every glyph. Use
// only for text rendered ON the bar (inside a Lib.Pill); text on cards/popups
// should stay a plain Text.
Text {
    style: BarStyle.current === "ghost" ? Text.Outline : Text.Normal
    styleColor: Qt.rgba(0, 0, 0, 1)
}
