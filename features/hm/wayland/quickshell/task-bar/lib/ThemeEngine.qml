import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property var data: ({})

    FileView {
        id: themeFile
        path: Quickshell.env("HOME") + "/.config/theme/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            // A watched file can be read mid-write (the theme tool is not
            // guaranteed atomic), yielding truncated JSON. Keep the last-good
            // palette on a parse failure instead of throwing and blanking colours.
            try {
                root.data = JSON.parse(themeFile.text());
            } catch (e) {}
        }
    }

    // mode -> isDarkMode (consumers still read this; JSON carries "gruvbox-dark")
    readonly property bool isDarkMode: ((root.data.mode ?? "dark").indexOf("dark") >= 0)

    // Surfaces
    readonly property color bgMain: root.data.colors?.bgMain ?? "#1d2021"
    readonly property color bgCard: root.data.colors?.bgCard ?? "#282828"
    readonly property color bgItem: root.data.colors?.bgItem ?? "#3c3836"
    readonly property color bgItemHover: root.data.colors?.bgItemHover ?? "#504945"
    readonly property color bgWidget: root.data.colors?.bgCard ?? "#282828"

    // Pill (floating-capsule) fill: translucent bgCard so the bar can go
    // transparent and pills frost over the wallpaper (Hyprland blurs behind the
    // bar layer). Opaque legibility fallback = set bgPillOpacity to 1.0 (or add
    // a solid "bgPill" hex to colors.json, which is used verbatim when present).
    readonly property real bgPillOpacity: root.data.colors?.bgPillOpacity ?? 0.64
    readonly property color bgPill: root.data.colors?.bgPill
        ?? Qt.rgba(bgCard.r, bgCard.g, bgCard.b, bgPillOpacity)

    // Text
    readonly property color textPrimary: root.data.colors?.textPrimary ?? "#ebdbb2"
    readonly property color textSecondary: root.data.colors?.textSecondary ?? "#a89984"
    readonly property color textOnAccent: root.data.colors?.textOnAccent ?? "#1d2021"
    readonly property color textOnAccent2: root.data.colors?.textPrimary ?? "#ebdbb2"

    // Accents
    readonly property color accent: root.data.colors?.accent ?? "#87b158"
    readonly property color accentBlue: root.data.colors?.accentBlue ?? "#83a598"
    readonly property color accentRed: root.data.colors?.accentRed ?? "#fb4934"
    readonly property color accentSlider: root.data.colors?.accentSlider ?? "#8ec07c"
    readonly property color accentSlider2: root.data.colors?.accentOrange ?? "#fe8019"
    readonly property color accentGreen: root.data.colors?.accentGreen ?? "#b8bb26"
    readonly property color accentYellow: root.data.colors?.accentYellow ?? "#fabd2f"
    readonly property color accentOrange: root.data.colors?.accentOrange ?? "#fe8019"
    readonly property color accentPurple: root.data.colors?.accentPurple ?? "#d3869b"

    // Lines / fills (no JSON key -> derive/static; border maps to borderInactive)
    readonly property color border: root.data.colors?.borderInactive ?? "#595959"
    readonly property color outline: Qt.rgba(1, 1, 1, 0.10)
    readonly property color subtleFill: Qt.rgba(1, 1, 1, 0.05)
    readonly property color subtleFillHover: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hoverSpotlight: Qt.rgba(1, 1, 1, 0.14)
    readonly property color weatherIcon: root.data.colors?.textSecondary ?? "#9da9a0"

    // Sizing (static; no JSON)
    readonly property int radiusOuter: 12
    readonly property int radiusInner: 16
    readonly property int padCard: 12
    readonly property int gapCard: 10
    readonly property int btnH: 54
    readonly property int sliderH: 24

    // Fonts (rename from JSON keys)
    readonly property string textFont: root.data.fonts?.ui ?? "Manrope"
    readonly property string iconFont: root.data.fonts?.icon ?? "JetBrainsMono Nerd Font"
    // Font Awesome (Solid) for glyphs the Nerd Font patch lacks, e.g. fa-memory
    // (U+F538). Add `fonts.awesome` to the Nix theme seam to override.
    readonly property string faFont: root.data.fonts?.awesome ?? "Font Awesome 7 Free Solid"
}
