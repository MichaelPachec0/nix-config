import QtQuick
import ".." as Xp

// Same geometry as Luna: this is a reskin, not a relayout. Only colors and the
// pulse accent change, which is the property that makes the palette seam
// worth having. ui/uiBold are written out explicitly even though they match
// Theme.qml's own Luna defaults -- Gruvbox does not need a different UI
// font, but leaving the override in place (rather than omitting it because
// the value happens to coincide) keeps every color-and-typography property
// listed here, so a future skim of this file never has to cross-reference
// Theme.qml to know whether an omission was deliberate or a miss. Every
// other Theme.qml property (metrics, switches, pulseDuration,
// comboVisibleRows, banner, glyph, uiSize) is inherited on purpose --
// palettes recolor, they do not relayout (see Theme.qml's own boundary
// comment).
Xp.Theme {
    face: "#3c3836"
    faceLight: "#665c54"
    faceShadow: "#282828"
    faceDark: "#1d2021"
    fieldBg: "#282828"
    fieldText: "#ebdbb2"
    fieldBorder: "#665c54"
    fieldDisabled: "#32302f"
    bannerFrom: "#458588"
    bannerTo: "#83a598"
    bannerText: "#fbf1c7"
    bannerSubtext: "#d5c4a1"
    buttonFrom: "#504945"
    buttonTo: "#3c3836"
    buttonBorder: "#665c54"
    buttonText: "#ebdbb2"
    defaultGlowFrom: "#d79921"
    defaultGlowTo: "#fabd2f"
    focusRing: "#ebdbb2"
    errorText: "#fb4934"
    infoText: "#a89984"
    ui: "Tahoma"
    uiBold: "Tahoma"
}
