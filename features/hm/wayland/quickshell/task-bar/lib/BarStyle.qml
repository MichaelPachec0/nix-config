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
    // The extrusion VECTOR: how far the black body is thrown, per axis. Negative
    // values throw it up / left if you ever want the light coming from below.
    readonly property int glyphLiftX: 2
    readonly property int glyphLiftY: 4
    // One copy per pixel along the LONGER axis, so the body stays solid rather
    // than breaking into separate ghosts on a diagonal throw. Derived, not set:
    // it is a consequence of the vector, and letting it drift out of sync with
    // the vector is what produces gaps.
    readonly property int glyphLiftSteps: Math.max(Math.abs(root.glyphLiftX), Math.abs(root.glyphLiftY))
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
    // glyphGlowOffsetX / Y bias the whole halo, on top of it being centred on the
    // extrusion's midpoint. The body runs down-right, so a purely centred halo
    // sits slightly behind its leading edge; a positive bias pushes it back
    // under the body. Both axes so the halo can be aimed independently of the
    // throw -- e.g. a wider X than the body for a side-lit look.
    readonly property color glyphGlowColor: "#ffffff"
    readonly property real glyphGlowAlpha: 0.10
    readonly property real glyphGlowSpread: 1
    readonly property int glyphGlowOffsetX: 2
    readonly property int glyphGlowOffsetY: 2
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

    // Runtime lever for the halo: `bar-glow off` / `bar-glow on`. Same state-file
    // mechanism as bar-style above, and because consumers bind this property
    // rather than re-reading a file, toggling it hot-swaps with no reload --
    // which matters here, since BarText.qml is one of the files Quickshell's hot
    // reload does NOT pick up, so a code-level knob would need a full restart.
    //
    // Defaults ON when the file is absent or unreadable: the halo is part of the
    // intended look, so a missing state file should not silently drop it.
    property bool glyphGlowEnabled: true

    FileView {
        id: glowFile
        path: root._stateDir + "/bar-glow"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: root.glyphGlowEnabled = true
        onLoaded: {
            var t = (glowFile.text() || "").trim().toLowerCase();
            root.glyphGlowEnabled = !(t === "off" || t === "0" || t === "false" || t === "no");
        }
    }
}
