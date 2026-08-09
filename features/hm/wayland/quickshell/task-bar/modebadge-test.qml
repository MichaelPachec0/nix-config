// Headless check for lib/ModeBadge.qml. Run:
//     quickshell -p modebadge-test.qml
//
// Lives at the config ROOT (not beside the component): `quickshell -p` makes
// the entrypoint's parent the config root. That placement is not what makes
// lib/ModeBadge.qml's `import "modefmt.js" as ModeFmt` resolve, though: like
// any relative QML import, it resolves relative to ModeBadge.qml's own
// directory (lib/), regardless of where the entrypoint sits (same reasoning
// as modeoverlay-test.qml, wakeservice-test.qml and routerpopup-size-test.qml).
//
// Wraps the badge in a Lib.Pill, mirroring how desktop/ModePill.qml (and the
// coming desktop/ModeOverlay.qml) actually use it, with a stub theme carrying
// every token Lib.Pill and Lib.ModeBadge read off it. Lib.BarText itself reads
// the BarStyle singleton rather than theme, so nothing further is needed for
// it. Creates no PanelWindow, so it maps no Wayland surface.
import QtQuick
import Quickshell
import "lib" as Lib

ShellRoot {
    id: harness

    property int pass: 0
    property int fail: 0
    function check(name, cond, detail) {
        if (cond) { harness.pass++; console.log("  ok   " + name + "   " + (detail || "")); }
        else { harness.fail++; console.log("  FAIL " + name + "   " + (detail || "")); }
    }

    QtObject {
        id: stubTheme
        readonly property color bgPill: "#282828"
        readonly property color border: "#595959"
        readonly property color accent: "#87b158"
        readonly property string faFont: "Font Awesome 7 Free Solid"
        readonly property string iconFont: "JetBrainsMono Nerd Font"
    }

    // A valid hex codepoint (fa-desktop, U+F108) with a label that changes
    // mid-run, to prove the badge tracks svc.label() live rather than
    // snapshotting it at creation.
    QtObject {
        id: svcValid
        property string cp: "f108"
        property string lbl: "Resize"
        function iconCp() { return svcValid.cp; }
        function label() { return svcValid.lbl; }
    }

    // Malformed codepoint: the guard Task 1 put in glyphFor, replacing the old
    // ModePill.qml's direct String.fromCharCode(parseInt(...)) call, which
    // painted a garbage glyph (U+0000) instead of drawing nothing.
    QtObject {
        id: svcMalformed
        readonly property string cp: "not-hex"
        function iconCp() { return svcMalformed.cp; }
        function label() { return "Broken"; }
    }

    // Empty codepoint: the ordinary "this submap has no icon" case.
    QtObject {
        id: svcEmpty
        readonly property string cp: ""
        function iconCp() { return svcEmpty.cp; }
        function label() { return "NoIcon"; }
    }

    Lib.Pill {
        id: pillValid
        theme: stubTheme
        ringColor: stubTheme.accent
        Lib.ModeBadge { id: badgeValid; theme: stubTheme; svc: svcValid }
    }
    Lib.Pill {
        id: pillMalformed
        theme: stubTheme
        ringColor: stubTheme.accent
        Lib.ModeBadge { id: badgeMalformed; theme: stubTheme; svc: svcMalformed }
    }
    Lib.Pill {
        id: pillEmpty
        theme: stubTheme
        ringColor: stubTheme.accent
        Lib.ModeBadge { id: badgeEmpty; theme: stubTheme; svc: svcEmpty }
    }
    // svc is null before HyprSubmapService's first Hyprland event lands;
    // ModeBadge must not throw or render junk while it is.
    Lib.Pill {
        id: pillNull
        theme: stubTheme
        ringColor: stubTheme.accent
        Lib.ModeBadge { id: badgeNull; theme: stubTheme; svc: null }
    }

    // ModeBadge declares its two BarText children in fixed order: the glyph
    // first, the label second. Neither is given an id (the brief's ModeBadge.qml
    // is used verbatim), so index into the RowLayout's visual children instead.
    function glyphItem(badge) { return badge.children[0]; }
    function labelItem(badge) { return badge.children[1]; }

    Component.onCompleted: Qt.callLater(function () {
        console.log("MODEBADGE-TEST");

        // Font Awesome's private-use-area glyphs render invisibly in a plain
        // terminal, so log the codepoint rather than the raw character.
        function cpOf(s) { return s.length ? "U+" + s.charCodeAt(0).toString(16) : "(empty)"; }

        // --- a valid hex codepoint produces a non-empty glyph -------------
        harness.check("valid cp yields a non-empty glyph",
                       badgeValid.glyph !== "", "glyph=" + cpOf(badgeValid.glyph));
        harness.check("valid cp glyph matches String.fromCharCode(0xf108)",
                       badgeValid.glyph === String.fromCharCode(0xf108),
                       "glyph=" + cpOf(badgeValid.glyph));
        harness.check("valid cp glyph BarText is visible",
                       harness.glyphItem(badgeValid).visible === true);
        harness.check("valid cp glyph BarText text matches badge.glyph",
                       harness.glyphItem(badgeValid).text === badgeValid.glyph);

        // --- malformed codepoint produces no glyph -------------------------
        harness.check("malformed cp yields an empty glyph",
                       badgeMalformed.glyph === "", "glyph=" + cpOf(badgeMalformed.glyph));
        harness.check("malformed cp glyph BarText is not visible",
                       harness.glyphItem(badgeMalformed).visible === false);
        harness.check("malformed cp does not paint U+0000 (the bug Task 1 fixed)",
                       harness.glyphItem(badgeMalformed).text !== String.fromCharCode(0));

        // --- empty codepoint is the same as malformed, not a crash ---------
        harness.check("empty cp yields an empty glyph",
                       badgeEmpty.glyph === "");
        harness.check("empty cp glyph BarText is not visible",
                       harness.glyphItem(badgeEmpty).visible === false);

        // --- svc: null is guarded, not a binding error ----------------------
        harness.check("null svc yields an empty glyph",
                       badgeNull.glyph === "");
        harness.check("null svc glyph BarText is not visible",
                       harness.glyphItem(badgeNull).visible === false);
        harness.check("null svc label is empty, not a thrown error",
                       harness.labelItem(badgeNull).text === "");

        // --- the label tracks svc.label(), including live changes ----------
        harness.check("label text tracks svc.label() at creation",
                       harness.labelItem(badgeValid).text === "Resize");
        svcValid.lbl = "Group";
        harness.check("label text tracks svc.label() after it changes",
                       harness.labelItem(badgeValid).text === "Group");

        console.log("MODEBADGE-TEST " + harness.pass + "/" + (harness.pass + harness.fail));
        Qt.exit(harness.fail === 0 ? 0 : 1);
    });
}
