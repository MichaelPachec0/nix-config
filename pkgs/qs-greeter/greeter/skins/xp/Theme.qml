import QtQuick

// The one place literal colors are allowed in this skin. Every widget under
// widgets/ takes a `theme` property and reads exclusively through it --
// never a literal `#rrggbb` -- so a palette swap (this file's defaults vs a
// palette/*.qml override, e.g. Task 12's Gruvbox) is a single-object
// substitution, not a hunt through widget code. Checkable with
// `grep -rn '#[0-9A-Fa-f]\{6\}' skins/xp/widgets/`.
QtObject {
    // palette
    property color face: "#ECE9D8"
    property color faceLight: "#FFFFFF"
    property color faceShadow: "#ACA899"
    property color faceDark: "#716F64"
    property color fieldBg: "#FFFFFF"
    property color fieldText: "#000000"
    property color fieldBorder: "#7F9DB9"
    property color fieldDisabled: "#EFEFEF"
    property color bannerFrom: "#0A246A"
    property color bannerTo: "#3A6EA5"
    property color bannerText: "#FFFFFF"
    property color bannerSubtext: "#C8D8F0"
    property color buttonFrom: "#FFFFFF"
    property color buttonTo: "#ECE9D8"
    property color buttonBorder: "#8E8F8F"
    property color buttonText: "#000000"
    property color defaultGlowFrom: "#3A80D8"
    property color defaultGlowTo: "#9CC4F0"
    property color focusRing: "#000000"
    property color errorText: "#A00000"
    property color infoText: "#303030"

    // metrics
    property int bevel: 1
    property int radius: 3
    property int controlHeight: 22
    property int rowSpacing: 10
    property int dialogPad: 16
    property int bannerHeight: 64

    // fonts
    property string ui: "Tahoma"
    property string uiBold: "Tahoma"
    property string banner: "Tahoma"
    property string glyph: "Marlett"
    property int uiSize: 12

    // switches
    property bool useGradients: true
    property bool useRoundedButtons: true
    property bool pulseDefaultButton: true

    // chrome behavior
    //
    // The boundary this file draws, so it does not get relitigated per
    // widget in a future task: a palette controls color, typography, and
    // chrome BEHAVIOR (does the default button pulse, how fast, how many
    // rows a popup shows before it scrolls) -- anything a skin variant
    // might plausibly want to dial differently. Per-widget default
    // GEOMETRY (a dialog defaulting to 420px wide, a balloon body to
    // 220px) is a widget default, not a palette concern -- a palette
    // recolors, it does not relayout -- and stays a literal in the widget
    // that owns it.
    property int pulseDuration: 900
    property int comboVisibleRows: 8
}
