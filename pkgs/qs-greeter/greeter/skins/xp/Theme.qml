import QtQuick
import "XpCss.js" as XpCss

// The one place literal colors are allowed in this skin. Every widget under
// widgets/ takes a `theme` property and reads exclusively through it --
// never a literal `#rrggbb` -- so a palette swap (this file's defaults vs a
// palette/*.qml override, e.g. Gruvbox) is a single-object substitution, not
// a hunt through widget code. Checkable with dev/tests/no-literal-colors.sh.
//
// The Luna defaults themselves are not written here. They are transcribed
// from XP.css in XpCss.js, which carries that project's attribution and
// license for the whole file rather than repeating it beside each borrowed
// value; this file only decides what to CALL each of them and which ones
// this skin needs. The split is the point: XpCss.js is what upstream says
// and can be diffed against it directly, Theme.qml is this skin's
// vocabulary. A palette (palettes/*.qml) overrides the vocabulary and never
// touches XpCss.js.
//
// The handful of values below that are NOT from XP.css are marked as such
// individually -- XP.css is a widget stylesheet and has nothing to say
// about, for instance, a login dialog's status text or the Windows flag.
QtObject {
    id: theme

    // --- dialog face ---
    property color face: XpCss.VARIABLES.surface
    property color faceLight: XpCss.VARIABLES.buttonHighlight
    // Not from XP.css: the greyed edge and shadow this skin uses for the
    // dialog frame and the engraved groove above the button row. XP.css
    // draws its window frame in Luna blue because every one of its windows
    // has a title bar; this dialog does not.
    property color faceShadow: "#ACA899"
    property color faceDark: "#716F64"
    property color windowFrame: XpCss.VARIABLES.windowFrame
    // The engraved groove: a dark hairline with a light hairline under it.
    // A single grey line in the same place reads as a border, not as a
    // groove cut into the face.
    property color grooveDark: "#ACA899"
    property color grooveLight: XpCss.VARIABLES.buttonHighlight

    // --- text fields ---
    property color fieldBg: "#FFFFFF"
    property color fieldText: "#000000"
    // A single flat slate-blue hairline -- NOT the sunken two-tone bevel of
    // Windows Classic/9x, which is the most common mistake in XP
    // recreations and which this skin used to draw on top of the hairline,
    // producing a muddy double border.
    property color fieldBorder: XpCss.FORMS.selectBorder
    // Not from XP.css: it styles disabled controls via opacity rather than
    // with dedicated colors.
    property color fieldDisabled: "#F5F4EA"
    property color fieldDisabledText: "#ACA899"
    property color selectionBg: XpCss.VARIABLES.dialogBlue
    property color selectionText: "#FFFFFF"

    // --- banner ---
    // XP.css's title-bar ramp. Five of its eight stops carry the shape; the
    // other three repeat a value to hold it flat across a span, which a
    // GradientStop list expresses by position alone (see XpBanner).
    property color bannerTop: XpCss.stopColor(XpCss.WINDOW.titleBar, 0.0)
    property color bannerUpper: XpCss.stopColor(XpCss.WINDOW.titleBar, 0.08)
    property color bannerMid: XpCss.stopColor(XpCss.WINDOW.titleBar, 0.40)
    property color bannerLower: XpCss.stopColor(XpCss.WINDOW.titleBar, 0.88)
    property color bannerFoot: XpCss.stopColor(XpCss.WINDOW.titleBar, 1.0)
    property color bannerText: "#FFFFFF"
    // Not from XP.css: it has no subtitle line in a title bar.
    property color bannerSubtext: "#C8DCF6"
    property color bannerShadow: XpCss.WINDOW.titleBarTextShadow
    // Outermost and innermost of XP.css's six window-frame insets.
    property color frameOuter: XpCss.WINDOW.frameShadow[0]
    property color frameInner: XpCss.WINDOW.frameShadow[3]

    // --- brand panel ---
    // Not from XP.css: it styles generic windows and has no logon dialog.
    // These are sampled from assets/img/windows_xp.avif, the reference shot
    // of the real Log On to Windows dialog, with ImageMagick rather than by
    // eye -- the periwinkle panel in particular is a color most
    // recreations guess far too saturated.
    property color brandPanel: "#7A9AEF"
    // The panel is not flat: it carries a soft lighter wash toward the
    // upper right, behind and above the wordmark.
    property color brandPanelLight: "#96AEF5"
    property color brandText: "#FFFFFF"
    // The "xp" set beside the Windows wordmark, in its orange-red.
    property color brandAccent: "#F4511E"
    // The separator under the brand panel is a HORIZONTAL ramp that starts
    // and ends in the panel's own blue and peaks warm just left of centre.
    // Reading it as a flat orange rule (or as a full-width strip) is the
    // detail that gives away a reproduction at a glance.
    property color dividerEdge: "#6F8AD9"
    property color dividerMid: "#A88D86"
    property color dividerPeak: "#F8953A"

    // --- buttons (Luna) ---
    property color btnFaceTop: XpCss.stopColor(XpCss.BUTTON.face, 0.0)
    property color btnFaceMid: XpCss.stopColor(XpCss.BUTTON.face, 0.86)
    property color btnFaceBottom: XpCss.stopColor(XpCss.BUTTON.face, 1.0)
    property color btnPressTop: XpCss.stopColor(XpCss.BUTTON.active, 0.0)
    property color btnPressUpper: XpCss.stopColor(XpCss.BUTTON.active, 0.08)
    property color btnPressLower: XpCss.stopColor(XpCss.BUTTON.active, 0.94)
    property color btnPressBottom: XpCss.stopColor(XpCss.BUTTON.active, 1.0)
    property color buttonBorder: XpCss.BUTTON.border
    property color buttonText: "#000000"
    property color hoverGlowOuter: XpCss.BUTTON.hoverShadow[0]
    property color hoverGlowUpper: XpCss.BUTTON.hoverShadow[1]
    property color hoverGlowLower: XpCss.BUTTON.hoverShadow[2]
    property color hoverGlowBottom: XpCss.BUTTON.hoverShadow[3]
    property color focusGlowOuter: XpCss.BUTTON.focusShadow[0]
    property color focusGlowUpper: XpCss.BUTTON.focusShadow[1]
    property color focusGlowLower: XpCss.BUTTON.focusShadow[2]
    property color focusGlowBottom: XpCss.BUTTON.focusShadow[3]
    // Not from XP.css: Windows' own dotted keyboard-focus rectangle, which
    // is drawn by the OS rather than by a stylesheet.
    property color focusRing: "#000000"

    // --- Windows flag ---
    // Not from XP.css (it ships no flag): brand quadrant colors, in reading
    // order -- top-left, top-right, bottom-left, bottom-right.
    property color flagRed: "#F65314"
    property color flagGreen: "#7CBB00"
    property color flagBlue: "#00A1F1"
    property color flagYellow: "#FFB900"

    // --- status text ---
    // Not from XP.css: a login dialog's error and status lines have no
    // equivalent in a widget stylesheet.
    property color errorText: "#A00000"
    property color infoText: "#000000"
    property color mutedText: "#5A5A50"

    // --- metrics ---
    property int bevel: 1
    property int radius: XpCss.BUTTON.borderRadius
    property int controlHeight: XpCss.FORMS.controlHeight
    property int rowSpacing: 10
    property int dialogPad: 16
    // Height of the plain title-bar band, used on its own by the dialogs
    // that have no brand panel (Shut Down, the fatal screen).
    property int bannerHeight: XpCss.WINDOW.titleBarHeight
    // The logon dialog's brand panel and the separator beneath it. Both
    // measured from the reference shot.
    property int brandPanelHeight: 86
    property int dividerHeight: 5
    // Width of the right-aligned label column beside each field. XP puts the
    // label to the LEFT of its box on this dialog, not stacked above it --
    // see XpTextField's own note.
    property int labelColumnWidth: 78

    // --- fonts ---
    // XP.css's own font stack is deliberately not used -- see XpCss.js. The
    // SIZE is: 11px on controls, which is Tahoma 8pt at the 96dpi XP
    // shipped on.
    property string ui: "Tahoma"
    property string uiBold: "Tahoma"
    property string banner: "Tahoma"
    property string glyph: "Marlett"
    property int uiSize: XpCss.BUTTON.fontSize
    // XP.css .title-bar font-size.
    property int titleSize: XpCss.WINDOW.titleFontSize
    property int smallSize: 10
    // Brand panel typography, measured from the reference shot. The
    // wordmark is the one place this dialog sets type large.
    property int wordmarkSize: 34
    property int wordmarkAccentSize: 16
    property int editionSize: 17

    // --- switches ---
    property bool useGradients: true
    property bool useRoundedButtons: true
    // OFF by default: XP's default button does not pulse, it wears the
    // static blue focus ring. Kept as a lever because it was this skin's
    // previous behavior and someone may want it back.
    property bool pulseDefaultButton: false
    // Draw the Windows flag in the banner. A palette that is not pretending
    // to be Windows (Gruvbox) turns this off rather than recoloring it into
    // something that is still recognizably the flag.
    property bool showFlag: true

    // chrome behavior
    //
    // The boundary this file draws, so it does not get relitigated per
    // widget in a future task: a palette controls color, typography, and
    // chrome BEHAVIOR (does the default button pulse, how fast, how many
    // rows a popup shows before it scrolls) -- anything a skin variant
    // might plausibly want to dial differently. Per-widget default
    // GEOMETRY (a dialog defaulting to 442px wide, a balloon body to
    // 220px) is a widget default, not a palette concern -- a palette
    // recolors, it does not relayout -- and stays a literal in the widget
    // that owns it.
    property int pulseDuration: 900
    property int comboVisibleRows: 8
}
