import QtQuick
import Quickshell

// Headless gallery/test harness for the XP widget kit (Task 9). It is the
// same "instantiate every widget in every state" gallery the brief's Step 5
// describes, but driven for CI/headless verification rather than eyeballed
// in a nested compositor -- this process must never be run interactively
// against the user's real session (it steals no focus and opens no visible
// window: QT_QPA_PLATFORM=offscreen is how it is meant to be run).
//
// The widget kit lives under greeter/skins/xp/, which default.nix never
// ships to dev/ (see its own comment on `src = ./greeter`), so this file
// cannot import it directly -- Quickshell sandboxes QML imports to the
// entrypoint's own directory, and dev/tests/ is outside greeter/. xp-kit/
// is a tree of committed, relative, `ln -sr`-built symlinks that mirror
// greeter/skins/xp/'s own layout one level under this file, exactly the
// technique screens/{Log,Settings,SettingsMerge.js} already use to reach
// one directory up from a different entrypoint. Depth is preserved (not
// flattened) because palettes/Luna.qml's own `import "../Theme.qml"`
// resolves relative to the symlink's own apparent path, not its target --
// flattening it would silently break that import.
import "xp-kit" as XpTheme
import "xp-kit/palettes" as XpPalettes
import "xp-kit/widgets" as XpWidgets

ShellRoot {
    id: root

    property int pass: 0
    property int total: 0

    function ok(name, cond) {
        root.total++;
        if (cond) root.pass++;
        else console.log("GALLERY-TEST CASE FAIL: " + name);
    }

    function eq(name, got, want) {
        root.total++;
        if (got === want) root.pass++;
        else console.log("GALLERY-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
    }

    XpTheme.Theme { id: theme }
    XpPalettes.Luna { id: luna }

    Item {
        id: gallery
        width: 1600
        height: 1200

        // --- XpButton: normal, default (pulsing), disabled ---
        XpWidgets.XpButton { id: btnNormal; theme: theme; text: "OK" }
        XpWidgets.XpButton { id: btnDefault; theme: theme; text: "OK"; isDefault: true }
        XpWidgets.XpButton { id: btnDisabled; theme: theme; text: "OK"; enabled: false }

        // --- XpTextField: normal, password (echo), disabled ---
        XpWidgets.XpTextField { id: fieldNormal; theme: theme; label: "User name:"; text: "michael" }
        XpWidgets.XpTextField { id: fieldPassword; theme: theme; label: "Password:"; echo: true; text: "secret" }
        XpWidgets.XpTextField { id: fieldDisabled; theme: theme; label: "User name:"; enabled: false }

        // --- XpComboBox: normal (with a model), disabled ---
        XpWidgets.XpComboBox { id: combo; theme: theme; model: ["Alice", "Bob", "Carol"]; currentIndex: 0 }
        XpWidgets.XpComboBox { id: comboDisabled; theme: theme; model: ["Alice"]; currentIndex: 0; enabled: false }

        // --- XpBanner ---
        XpWidgets.XpBanner {
            id: banner
            theme: theme
            title: "Log On to Windows"
            subtitle: "Microsoft Windows XP  Professional"
        }

        // --- XpBalloon, anchored to fieldNormal ---
        XpWidgets.XpBalloon {
            id: balloon
            theme: theme
            text: "The user name or password is incorrect."
            target: fieldNormal
        }

        // --- XpDialog, with a plain content item and two buttons ---
        Item { id: dlgContent; implicitWidth: 200; implicitHeight: 40 }
        XpWidgets.XpDialog {
            id: dialog
            theme: theme
            bannerTitle: "Log On to Windows"
            bannerSubtitle: "Microsoft Windows XP  Professional"
            contentItem: dlgContent
            buttons: [
                { text: "OK", isDefault: true },
                { text: "Cancel" }
            ]
        }

        // --- XpMessageBox ---
        XpWidgets.XpMessageBox {
            id: msgbox
            theme: theme
            text: "The system is shutting down. Any unsaved changes will be lost."
        }
    }

    Timer {
        // A short delay, not zero: several widgets (XpBalloon's reposition,
        // XpDialog's contentItem reparent) run from Component.onCompleted
        // or a property-change handler and need one event-loop turn to
        // settle before their geometry is trustworthy to assert on.
        interval: 100
        running: true
        onTriggered: root._runChecks()
    }

    function _runChecks() {
        // Theme / Luna: Luna's defaults ARE Theme's defaults (Task 12's
        // Gruvbox is the first real override) -- confirm that identity
        // holds for one representative color and one metric, and that Luna
        // is a distinct instance (a shared singleton would defeat a
        // runtime palette swap between two live widgets).
        eq("luna.face equals theme.face (no override)", luna.face, theme.face);
        eq("luna.controlHeight equals theme.controlHeight", luna.controlHeight, theme.controlHeight);
        ok("luna is not the same object as theme", luna !== theme);

        // --- XpButton ---
        // Floor is 75, not 80: that is XpButton's own minimum, and it is the
        // width a standard Windows dialog push button has always been. The
        // old 80 was this test's invention rather than the widget's.
        ok("btnNormal.implicitWidth sane", btnNormal.implicitWidth >= 75 && btnNormal.implicitWidth < 1000);
        ok("btnNormal.implicitHeight sane", btnNormal.implicitHeight > 0 && btnNormal.implicitHeight < 200);
        ok("btnNormal at full opacity", btnNormal.opacity === 1.0);
        ok("btnDisabled dimmer than btnNormal", btnDisabled.opacity < btnNormal.opacity);
        // The default button no longer pulses, and that is the fix rather
        // than a regression: XP's default button wears a STATIC blue inset
        // ring (XP.css's :focus box-shadows), and the pulse was invented
        // here. theme.pulseDefaultButton now defaults false, so what is
        // asserted is the ring, with the pulse checked as an opt-in lever
        // that still works when a palette turns it back on.
        eq("btnDefault shows the focus ring", btnDefault.testRing, "focus");
        eq("btnNormal shows no ring (not default, not hovered)", btnNormal.testRing, "");
        ok("btnDefault pulse NOT running (theme.pulseDefaultButton is off by default)",
            btnDefault.pulseRunning === false);
        ok("btnNormal pulse animation NOT running (not default)", btnNormal.pulseRunning === false);
        ok("btnDisabled pulse animation NOT running (disabled)", btnDisabled.pulseRunning === false);
        // Prove the lever is a lever and not dead code: flipping it on must
        // actually start the animation on the default button, and only on
        // the default button. Restored immediately so nothing below sees a
        // mutated theme.
        theme.pulseDefaultButton = true;
        ok("pulse starts when theme.pulseDefaultButton is turned on",
            btnDefault.pulseRunning === true);
        ok("pulse still does not run on a non-default button",
            btnNormal.pulseRunning === false);
        theme.pulseDefaultButton = false;
        ok("pulse stops again when the lever is turned back off",
            btnDefault.pulseRunning === false);

        // --- XpTextField ---
        ok("fieldNormal.implicitWidth sane", fieldNormal.implicitWidth >= 160);
        ok("fieldNormal.implicitHeight sane", fieldNormal.implicitHeight > 0);
        eq("fieldNormal echoMode is Normal", fieldNormal.echoMode, TextInput.Normal);
        eq("fieldPassword echoMode is Password", fieldPassword.echoMode, TextInput.Password);
        ok("fieldDisabled dimmer than fieldNormal", fieldDisabled.opacity < fieldNormal.opacity);

        // --- XpComboBox ---
        eq("combo.currentName reflects currentIndex", combo.currentName, "Alice");
        ok("combo popup starts closed", combo.popupOpen === false);
        combo.openPopup();
        ok("combo.openPopup() opens the popup", combo.popupOpen === true);
        eq("combo highlightIndex starts at currentIndex", combo.highlightIndex, 0);
        combo.moveHighlight(1);
        eq("combo.moveHighlight(1) advances highlightIndex", combo.highlightIndex, 1);
        combo.moveHighlight(1);
        eq("combo.moveHighlight(1) advances again", combo.highlightIndex, 2);
        combo.moveHighlight(1);
        eq("combo.moveHighlight(1) wraps around", combo.highlightIndex, 0);
        combo.moveHighlight(-1);
        eq("combo.moveHighlight(-1) wraps the other way", combo.highlightIndex, 2);
        combo.confirmHighlight();
        eq("combo.confirmHighlight() commits currentIndex", combo.currentIndex, 2);
        ok("combo.confirmHighlight() closes the popup", combo.popupOpen === false);
        ok("comboDisabled.openPopup() is a no-op when disabled", (function () {
            comboDisabled.openPopup();
            return comboDisabled.popupOpen === false;
        })());

        // --- XpBanner ---
        ok("banner.implicitWidth sane", banner.implicitWidth > 0);
        eq("banner.implicitHeight equals theme.bannerHeight", banner.implicitHeight, theme.bannerHeight);

        // --- XpBalloon ---
        ok("balloon.implicitWidth sane", balloon.implicitWidth > 0);
        ok("balloon.implicitHeight sane", balloon.implicitHeight > 0);
        // Tail-tip x should sit under the target's horizontal center once
        // _reposition() has run (see the Timer delay above).
        var targetCenter = fieldNormal.x + fieldNormal.width / 2;
        var balloonCenter = balloon.x + balloon.width / 2;
        ok("balloon centers itself on its target", Math.abs(balloonCenter - targetCenter) < 1);

        // --- XpDialog ---
        ok("dialog.implicitWidth sane", dialog.implicitWidth > 0);
        ok("dialog.implicitHeight sane", dialog.implicitHeight > theme.bannerHeight);
        eq("dialog reparents contentItem under itself", dlgContent.parent !== null && _isDescendantOf(dlgContent, dialog), true);

        // --- XpMessageBox ---
        ok("msgbox.implicitWidth sane", msgbox.implicitWidth > 0);
        ok("msgbox.implicitHeight sane", msgbox.implicitHeight > 0);
        var acceptedFired = false;
        msgbox.accepted.connect(function () { acceptedFired = true; });
        // buttons[0] is the sole OK button XpMessageBox wires up; drive its
        // onClicked the same way a real click would, since there is no
        // synthetic-mouse-click path under the offscreen QPA platform.
        _clickFirstButtonOf(msgbox);
        ok("msgbox OK button fires accepted()", acceptedFired === true);

        console.log("GALLERY-TEST " + (root.pass === root.total ? "PASS" : "FAIL") + " " + root.pass + "/" + root.total);
        Qt.quit();
    }

    function _isDescendantOf(item, ancestor) {
        var p = item.parent;
        while (p) {
            if (p === ancestor) return true;
            p = p.parent;
        }
        return false;
    }

    // XpMessageBox composes XpDialog internally and does not re-expose its
    // button Repeater, so the harness walks the (small, known) child tree
    // to find the instantiated XpButton and invoke its click() the way a
    // MouseArea would. This only reaches into implementation detail for
    // testing purposes; nothing outside this file relies on it.
    function _clickFirstButtonOf(msgBoxItem) {
        function findButton(item) {
            for (var i = 0; i < item.children.length; i++) {
                var c = item.children[i];
                if (typeof c.clicked === "function" && c.text !== undefined && c.isDefault !== undefined) {
                    return c;
                }
                var found = findButton(c);
                if (found) return found;
            }
            return null;
        }
        var btn = findButton(msgBoxItem);
        if (btn) btn.clicked();
    }
}
