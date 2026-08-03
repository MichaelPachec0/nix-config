pragma Singleton
import QtQuick // for the `color` type on glyphGlowColor below
import Quickshell
import Quickshell.Io

// Live bar look ("ghost" | "frosted"), toggled by the `bar-style` command via a
// state file kept OUTSIDE the ~/.config/quickshell repo symlink so it never
// dirties the repo. watchChanges -> hot-swaps with no reload. Defaults to
// "frosted" when the file is absent/invalid. A singleton so Pill and BarText
// read it without threading `theme` (or a style prop) to every glyph.
Singleton {
    id: root

    property string current: "frosted"

    // Shared depth for the frosted raised look, so anything that is NOT a
    // Lib.BarText (the router's signal-bar Rectangles, say) can cast the same
    // drop and stay on one depth plane with the glyphs. Read by BarText.lift and
    // by any hand-drawn glyph that wants to match.
    //
    // Only meaningful in frosted: ghost / ghost-glass use Text.Outline, a full
    // halo for legibility over raw wallpaper, which a directional drop fights.
    // Depth in px AND the number of extrusion steps: one copy per pixel, so the
    // body is solid rather than a detached second image.
    readonly property int glyphLift: 4
    // Horizontal component of the extrusion vector. Kept below glyphLift so the
    // body runs mostly straight down, matching Text.Raised's own direction.
    readonly property int glyphLiftX: 1
    readonly property real glyphLiftAlpha: 1.0

    // Faint halo behind the extruded body, so the shadow does not end on a hard
    // line against the pill. Drawn as copies nudged out in eight directions from
    // the body's midpoint -- symmetric by construction, so it cannot drift off
    // to one side the way a scaled copy does. No offscreen blur pass.
    //
    // glyphGlowSpread is the offset in PIXELS (not a scale factor). Keep it at
    // 1: past that the copies separate into distinct ghosts instead of reading
    // as one soft edge.
    //
    // glyphGlowAlpha is PER COPY. Eight of them overlap, so the visible edge
    // lands near 1-2x this value -- which is why it is far lower than it looks.
    //
    // glyphGlowOffsetX biases the whole halo sideways, on top of the centring.
    // The extrusion runs down-RIGHT, so a purely centred halo sits slightly
    // behind its left edge; a positive bias pushes it back under the body.
    readonly property color glyphGlowColor: "#ffffff"
    readonly property real glyphGlowAlpha: 0.06
    readonly property real glyphGlowSpread: 1
    readonly property int glyphGlowOffsetX: 1
    readonly property bool glyphLifted: root.current === "frosted"

    readonly property string _stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"

    FileView {
        id: file
        path: root._stateDir + "/bar-style"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var t = (file.text() || "").trim();
            root.current = (t === "ghost" || t === "ghost-glass") ? t : "frosted";
        }
    }
}
