import QtQuick
import Quickshell
import "xp-kit" as XpKit

// Construction-only smoke check for Skin.qml (and, transitively,
// SkinFatal.qml and LogonDialog.qml, which it instantiates): confirms the
// whole assembly loads headlessly with no undefined-property/ReferenceError
// warning, the same class of defect widgets-gallery.qml guards against for
// the widget kit (see its own header for why a clean PASS line does not by
// itself prove there is no theme.* typo -- the warning scan lives in this
// file's .sh runner, not here).
//
// Deliberately does NOT drive Session through any real auth transition:
// Skin.qml's LogonDialog reacts to Session.stateChanged regardless of its
// own `visible`, so doing that here would race logon-dialog-test.qml's own
// dialog instance for the same singletons. session/sessions are left null
// on purpose -- that is exactly the "greetd not available yet" moment
// every real boot passes through before shell.qml's onLoaded runs, and it
// is what routes this instance to SkinFatal rather than LogonDialog.
ShellRoot {
    id: root
    property int pass: 0
    property int total: 0
    function ok(name, cond) {
        total++;
        if (cond) pass++;
        else console.log("SKIN-SMOKE-TEST CASE FAIL: " + name);
    }

    XpKit.Skin {
        id: skin
    }

    Timer {
        interval: 100
        running: true
        onTriggered: {
            ok("skinConstructed", skin !== null);
            ok("noSessionRoutesToFatal", skin._fatal === true);
            ok("themeResolved", skin.theme !== null && skin.theme !== undefined);
            ok("paletteReflectsTheme", skin.palette === skin.theme);
            console.log("SKIN-SMOKE-TEST " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
            Qt.quit();
        }
    }
}
