import QtQuick
import ".." as Xp

// Same geometry as Luna: this is a reskin, not a relayout. Only colors and
// two switches change, which is the property that makes the palette seam
// worth having. ui/uiBold are written out explicitly even though they match
// Theme.qml's own Luna defaults -- Gruvbox does not need a different UI
// font, but leaving the override in place (rather than omitting it because
// the value happens to coincide) keeps every color-and-typography property
// listed here, so a future skim of this file never has to cross-reference
// Theme.qml to know whether an omission was deliberate or a miss. Every
// other Theme.qml property (metrics, remaining switches, pulseDuration,
// comboVisibleRows, banner font, glyph, the type sizes) is inherited on
// purpose -- palettes recolor, they do not relayout (see Theme.qml's own
// boundary comment).
//
// Two structural notes:
//
// showFlag is turned OFF rather than recolored. The Windows flag is not a
// decoration a palette can restate in its own colors -- a Gruvbox-tinted
// Windows flag is still a Windows flag, and this palette is not pretending
// to be Windows. The banner keeps its title and subtitle and simply starts
// at the left edge instead. That is also why the four flagXxx quadrant
// colors are NOT overridden here: nothing renders them.
//
// The button gradient keeps Luna's stop POSITIONS (the 86% break, the
// four-stop pressed curve) and changes only the colors. That break is what
// makes a button look moulded rather than filled, and it is geometry, not
// palette.
Xp.Theme {
    face: "#3c3836"
    faceLight: "#665c54"
    faceShadow: "#282828"
    faceDark: "#1d2021"
    windowFrame: "#1d2021"
    grooveDark: "#282828"
    grooveLight: "#665c54"

    fieldBg: "#282828"
    fieldText: "#ebdbb2"
    fieldBorder: "#665c54"
    fieldDisabled: "#32302f"
    fieldDisabledText: "#7c6f64"
    selectionBg: "#458588"
    selectionText: "#fbf1c7"

    bannerTop: "#504945"
    bannerUpper: "#3c3836"
    bannerMid: "#32302f"
    bannerLower: "#3c3836"
    bannerFoot: "#282828"
    bannerText: "#fbf1c7"
    bannerSubtext: "#d5c4a1"
    bannerShadow: "#1d2021"
    frameOuter: "#1d2021"
    frameInner: "#665c54"

    // The brand panel is structural chrome that LogonDialog always shows,
    // so it has to be restated here -- inheriting it would put a
    // periwinkle Windows panel in the middle of a Gruvbox dialog. The
    // separator keeps its blue-to-warm-to-blue SHAPE (that is geometry) and
    // only changes color, so it still reads as the same piece of chrome.
    brandPanel: "#32302f"
    brandPanelLight: "#3c3836"
    brandText: "#ebdbb2"
    brandAccent: "#fe8019"
    dividerEdge: "#282828"
    dividerMid: "#7c6f64"
    dividerPeak: "#d79921"

    btnFaceTop: "#665c54"
    btnFaceMid: "#504945"
    btnFaceBottom: "#3c3836"
    btnPressTop: "#282828"
    btnPressUpper: "#3c3836"
    btnPressLower: "#413d38"
    btnPressBottom: "#504945"
    buttonBorder: "#1d2021"
    buttonText: "#ebdbb2"

    hoverGlowOuter: "#fbf1c7"
    hoverGlowUpper: "#fabd2f"
    hoverGlowLower: "#d79921"
    hoverGlowBottom: "#b57614"
    focusGlowOuter: "#d3d3c0"
    focusGlowUpper: "#83a598"
    focusGlowLower: "#458588"
    focusGlowBottom: "#076678"
    focusRing: "#ebdbb2"

    errorText: "#fb4934"
    infoText: "#ebdbb2"
    mutedText: "#a89984"

    ui: "Tahoma"
    uiBold: "Tahoma"

    showFlag: false
}
