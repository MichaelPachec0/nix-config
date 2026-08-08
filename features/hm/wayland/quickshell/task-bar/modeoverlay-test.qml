// Headless construction check for desktop/ModeOverlay.qml. Run:
//     quickshell -p modeoverlay-test.qml
//
// Lives at the config ROOT (not a subdirectory): `quickshell -p` makes the
// entrypoint's parent the config root, and desktop/ModeOverlay.qml does
// `import "../lib" as Lib`, which resolves relative to ModeOverlay.qml's own
// directory regardless of where the entrypoint sits (same reasoning as
// modebadge-test.qml and routerpopup-size-test.qml).
//
// This is a CONSTRUCTION harness only. It proves the component builds without
// a QML error or warning -- a wrong import, a misspelled Wayland enum
// (WlrKeyboardFocus.None, WlrLayer.Overlay, ExclusionMode.Ignore), an
// unresolved Region -- and that the visibility predicate stays FALSE across
// every combination this file drives.
//
// It does NOT map a real Overlay-layer surface. Every instance below is
// pinned covered: false for the whole run, so `visible` can never evaluate
// true: mapping that surface would paint above the user's live desktop,
// including any fullscreen window, and this harness has no screen to observe
// the result on. Exercising the visible-true case (a real submap plus a real
// fullscreen window, checked with `hyprctl layers`) is Task 5's job, done
// interactively by a human on the live compositor, not here.
import QtQuick
import Quickshell
import "desktop" as Desktop

ShellRoot {
    id: harness

    property int pass: 0
    property int fail: 0
    function check(name, cond, detail) {
        if (cond) { harness.pass++; console.log("  ok   " + name + "   " + (detail || "")); }
        else { harness.fail++; console.log("  FAIL " + name + "   " + (detail || "")); }
    }

    // Stub theme carrying every token Lib.Pill and Lib.ModeBadge read off it,
    // matching modebadge-test.qml's stub.
    QtObject {
        id: stubTheme
        readonly property color bgPill: "#282828"
        readonly property color border: "#595959"
        readonly property color accent: "#87b158"
        readonly property string faFont: "Font Awesome 7 Free Solid"
        readonly property string iconFont: "JetBrainsMono Nerd Font"
    }

    // An "active submap" stub (non-empty current) so that in the covered:false
    // cases below, the ONLY reason visible must stay false is the covered
    // gate itself, not an incidentally-empty svc.
    QtObject {
        id: svcActive
        readonly property string current: "resize"
        function iconCp() { return "f108"; }
        function label() { return "Resize"; }
    }

    // The ordinary idle state: no submap active.
    QtObject {
        id: svcIdle
        readonly property string current: ""
        function iconCp() { return ""; }
        function label() { return ""; }
    }

    // Four instances spanning svc x locked. ALL four are covered: false for
    // the entire run -- see the HARD REQUIREMENT in the file header. This is
    // deliberately not the full covered x svc x locked matrix; the
    // covered:true leg is Task 5's, not this harness's.
    Desktop.ModeOverlay {
        id: ovActiveUnlocked
        theme: stubTheme
        svc: svcActive
        covered: false
        locked: false
        barHeight: 34
    }
    Desktop.ModeOverlay {
        id: ovActiveLocked
        theme: stubTheme
        svc: svcActive
        covered: false
        locked: true
        barHeight: 34
    }
    Desktop.ModeOverlay {
        id: ovIdleUnlocked
        theme: stubTheme
        svc: svcIdle
        covered: false
        locked: false
        barHeight: 34
    }
    Desktop.ModeOverlay {
        id: ovIdleLocked
        theme: stubTheme
        svc: svcIdle
        covered: false
        locked: true
        barHeight: 34
    }

    Component.onCompleted: Qt.callLater(function () {
        console.log("MODEOVERLAY-TEST");

        harness.check("active submap, unlocked, NOT covered stays hidden",
                       ovActiveUnlocked.visible === false,
                       "visible=" + ovActiveUnlocked.visible);
        harness.check("active submap, locked, not covered stays hidden",
                       ovActiveLocked.visible === false,
                       "visible=" + ovActiveLocked.visible);
        harness.check("idle submap, unlocked, not covered stays hidden",
                       ovIdleUnlocked.visible === false,
                       "visible=" + ovIdleUnlocked.visible);
        harness.check("idle submap, locked, not covered stays hidden",
                       ovIdleLocked.visible === false,
                       "visible=" + ovIdleLocked.visible);

        // implicitHeight tracks the bound barHeight without restating it (44
        // in the real shell, off taskbar.implicitHeight); 34 here just proves
        // the binding rather than hardcoding the real constant.
        harness.check("implicitHeight tracks the bound barHeight",
                       ovActiveUnlocked.implicitHeight === 34,
                       "implicitHeight=" + ovActiveUnlocked.implicitHeight);

        console.log("MODEOVERLAY-TEST " + harness.pass + "/" + (harness.pass + harness.fail));
        Qt.exit(harness.fail === 0 ? 0 : 1);
    });
}
