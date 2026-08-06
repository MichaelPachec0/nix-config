import QtQuick
import Quickshell
// See widgets-gallery.qml's own header for why this file cannot import
// greeter/skins/xp/ directly (Quickshell sandboxes QML imports to the
// entrypoint's own directory) and why xp-kit/ -- a tree of committed,
// relative symlinks one level under this file -- exists to reach it
// anyway, depth preserved so relative imports inside the mirrored files
// keep resolving correctly.
import "xp-kit" as XpKit
import "xp-kit/palettes" as XpPalettes
import "xp-kit/widgets" as XpWidgets
import "xp-kit/screens" as XpScreens

// Task 12 verification: this is the file that actually proves the
// palette/widget boundary Tasks 9-11 were built under, not just that
// Gruvbox.qml parses. Three independent claims, each backed by its own
// section below:
//
//   A. Every property Theme.qml declares is accounted for: the 21 colors
//      Gruvbox overrides (and none of them coincide with Luna's value --
//      that would silently defeat this whole check), the 2 font
//      properties Gruvbox re-states but does not change (ui/uiBold, both
//      "Tahoma" -- see Gruvbox.qml's own comment on why they are written
//      out anyway), and the 14 properties it inherits untouched (the ones
//      that drive layout, not color). This list is asserted to be
//      EXACTLY Theme.qml's own declared property set (via runtime
//      reflection, not copied from Theme.qml by eye) -- a property this
//      file forgets to categorize fails the totals check below rather
//      than silently passing as "inherited by omission".
//   B. A representative set of widgets AND both real screens (LogonDialog,
//      ShutDownDialog), each built twice -- once with theme: luna, once
//      with theme: gruvbox -- must report IDENTICAL implicit sizes, row
//      heights, and dialog overall size. This is the geometry-invariance
//      assertion: Gruvbox is a reskin, not a relayout, and this is what
//      would fail if some widget had cheated Task 9's "no literal colors"
//      rule by putting a metric where a color belonged (or vice versa).
//   C. The SAME widget pairs from B must report DIFFERENT rendered colors
//      (walked generically off each instance's own child Rectangle/Text
//      tree, not re-read from the theme objects the audit in A already
//      covers) -- proving the swap is not a no-op that would also pass a
//      naive geometry-only test.
//   D. An unregistered palette name, reaching Skin.qml directly (bypassing
//      the validation Settings/SettingsMerge.js would normally apply to a
//      real user-settings write), falls back to Luna rather than
//      resolving to an undefined theme.
//
// Deliberately headless and non-interactive: QT_QPA_PLATFORM=offscreen,
// no window, no focus stolen, must never be run against the user's real
// session (see this directory's other *-test.qml files for the same
// constraint).
ShellRoot {
    id: root
    property int pass: 0
    property int total: 0

    function ok(name, cond) {
        total++;
        if (cond) pass++;
        else console.log("PALETTE-TEST CASE FAIL: " + name);
    }
    function eq(name, got, want) {
        total++;
        if (got === want) pass++;
        else console.log("PALETTE-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
    }

    XpPalettes.Luna { id: luna }
    XpPalettes.Gruvbox { id: gruvbox }

    // === Part B/C fixtures: one luna-themed and one gruvbox-themed
    // instance of each widget/screen, side by side. session/sessions are
    // explicitly null (not omitted -- both are `required property var` on
    // LogonDialog, so an explicit null satisfies the requirement the same
    // way skin-smoke-test.qml's session-less Skin instance does): this
    // file measures BASELINE geometry only (implicit sizes, the two fixed
    // field rows, the dialog's overall size), which does not depend on a
    // real Session/Sessions backend, so wiring MockBackend here would only
    // add a shared-singleton race against nothing this file actually
    // checks.
    Item {
        id: gallery
        width: 2400
        height: 1200

        XpWidgets.XpButton { id: btnL; theme: luna; text: "Shut Down..."; isDefault: true }
        XpWidgets.XpButton { id: btnG; theme: gruvbox; text: "Shut Down..."; isDefault: true }

        XpWidgets.XpTextField { id: fieldL; theme: luna; label: "User name:"; text: "michael" }
        XpWidgets.XpTextField { id: fieldG; theme: gruvbox; label: "User name:"; text: "michael" }

        XpWidgets.XpComboBox { id: comboL; theme: luna; model: ["Alice", "Bob", "Carol"]; currentIndex: 0 }
        XpWidgets.XpComboBox { id: comboG; theme: gruvbox; model: ["Alice", "Bob", "Carol"]; currentIndex: 0 }

        XpWidgets.XpBanner {
            id: bannerL; theme: luna
            title: "Log On to Windows"; subtitle: "Microsoft Windows XP  Professional"
        }
        XpWidgets.XpBanner {
            id: bannerG; theme: gruvbox
            title: "Log On to Windows"; subtitle: "Microsoft Windows XP  Professional"
        }

        Item { id: dlgContentL; implicitWidth: 200; implicitHeight: 40 }
        Item { id: dlgContentG; implicitWidth: 200; implicitHeight: 40 }
        XpWidgets.XpDialog {
            id: dialogL; theme: luna
            bannerTitle: "Log On to Windows"; bannerSubtitle: "Microsoft Windows XP  Professional"
            contentItem: dlgContentL
            buttons: [{ text: "OK", isDefault: true }, { text: "Cancel" }]
        }
        XpWidgets.XpDialog {
            id: dialogG; theme: gruvbox
            bannerTitle: "Log On to Windows"; bannerSubtitle: "Microsoft Windows XP  Professional"
            contentItem: dlgContentG
            buttons: [{ text: "OK", isDefault: true }, { text: "Cancel" }]
        }

        XpScreens.LogonDialog { id: dlgL; theme: luna; session: null; sessions: null }
        XpScreens.LogonDialog { id: dlgG; theme: gruvbox; session: null; sessions: null }

        XpScreens.ShutDownDialog { id: sdL; theme: luna }
        XpScreens.ShutDownDialog { id: sdG; theme: gruvbox }
    }

    // === Part D fixture: Skin.qml driven DIRECTLY with an unregistered
    // palette name, per this task's requirement 4. SettingsMerge.js
    // validates skinSettings.xp.palette against meta.json's declared list
    // (["luna", "gruvbox"]) -- but only for the USER tier (see its
    // `_applyKey` "skinSettings" case); the Nix-owned defaults tier is
    // never validated at all. palette-test.sh points this whole process's
    // QSG_DEFAULTS at a fixture whose skinSettings.xp.palette is an
    // unregistered string for exactly that reason: it is the one way to
    // reach Skin.qml's own fallback (the `theme` property in Skin.qml)
    // without going through Settings' own validation, matching this
    // file's brief ("Settings validation would normally stop it, so drive
    // Skin directly"). XpKit.Settings below is the SAME per-directory
    // singleton instance Skin.qml itself reads (both reached through the
    // "xp-kit" import) -- see LogonDialog.qml's own comment on why a
    // *different* directory's Settings symlink would be the wrong
    // instance to poll.
    XpKit.Skin { id: fallbackSkin }

    Component.onCompleted: {
        var start = Date.now();
        var t = Qt.createQmlObject('import QtQuick; Timer { interval: 20; repeat: true }', root);
        t.triggered.connect(function () {
            var settled = XpKit.Settings.ready === true;
            if (!settled && Date.now() - start <= 2000) return;
            t.stop(); t.destroy();
            root._runChecks();
        });
        t.start();
    }

    // --- generic child-tree color harvester, used by Part C. Walks the
    // ACTUAL rendered Item tree (not the theme object) collecting every
    // reachable `color` and `border.color`, so this proves the widget
    // layer picked up the swap -- not just that the two palette objects
    // hold different values, which Part A already covers at the object
    // level. Rectangle.gradient stops are not QML `children` and so are
    // not reachable this way (Gradient/GradientStop are property values,
    // not child Items) -- this deliberately undercounts rather than risks
    // a false pass, and every widget here also exposes at least one flat
    // (non-gradient) color or a border.color that this walk does reach
    // (confirmed by reading each widget's source, not assumed). ---
    function _harvestColors(item, out) {
        if (item.color !== undefined) out.push(String(item.color));
        if (item.border !== undefined && item.border.color !== undefined)
            out.push(String(item.border.color));
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) root._harvestColors(kids[i], out);
    }

    function _runChecks() {
        // ================= Part A: property audit =================
        // Runtime reflection, not a hand-copied list: `for...in` on a
        // QtObject-derived instance enumerates every declared QML
        // property (confirmed empirically -- see this plan's own
        // scratch-tested reflection technique) plus each property's own
        // xChanged signal and objectName; both are filtered out below so
        // what remains is exactly Theme.qml's declared property set.
        var allProps = [];
        for (var k in luna) {
            if (typeof luna[k] === "function") continue;
            if (k === "objectName" || /Changed$/.test(k)) continue;
            allProps.push(k);
        }
        allProps.sort();

        var COLOR_PROPS = ["face", "faceLight", "faceShadow", "faceDark",
            "fieldBg", "fieldText", "fieldBorder", "fieldDisabled",
            "bannerFrom", "bannerTo", "bannerText", "bannerSubtext",
            "buttonFrom", "buttonTo", "buttonBorder", "buttonText",
            "defaultGlowFrom", "defaultGlowTo", "focusRing", "errorText", "infoText"];
        // Explicitly re-stated in Gruvbox.qml with the SAME value as
        // Luna's default (both "Tahoma") -- deliberate, not an omission
        // (see Gruvbox.qml's own comment): checked separately from
        // COLOR_PROPS because "overridden" and "differs from Luna" are
        // two different claims for exactly these two properties.
        var SAME_VALUE_OVERRIDE_PROPS = ["ui", "uiBold"];
        // Never mentioned in Gruvbox.qml at all -- inherited from
        // Theme.qml's own defaults. This is the set that must NOT differ
        // between palettes: it is what keeps Part B's geometry invariant
        // (the 6 metrics + comboVisibleRows) and what keeps chrome
        // behavior (switches, pulseDuration) and the two unused-today
        // font slots (banner, glyph, uiSize) identical too.
        var INHERITED_PROPS = ["banner", "glyph", "uiSize",
            "bevel", "radius", "controlHeight", "rowSpacing", "dialogPad", "bannerHeight",
            "useGradients", "useRoundedButtons", "pulseDefaultButton",
            "pulseDuration", "comboVisibleRows"];

        var accounted = COLOR_PROPS.concat(SAME_VALUE_OVERRIDE_PROPS, INHERITED_PROPS).sort();
        eq("every Theme.qml property is accounted for exactly once (21 colors + 2 same-value overrides + 14 inherited = 37)",
            JSON.stringify(accounted), JSON.stringify(allProps));

        COLOR_PROPS.forEach(function (p) {
            ok("color '" + p + "' differs between luna and gruvbox", luna[p] !== gruvbox[p]);
        });
        SAME_VALUE_OVERRIDE_PROPS.forEach(function (p) {
            ok("'" + p + "' is the SAME value in both (Gruvbox restates it deliberately, does not change it)",
                luna[p] === gruvbox[p]);
        });
        INHERITED_PROPS.forEach(function (p) {
            ok("inherited property '" + p + "' is identical in both (Gruvbox never mentions it)",
                luna[p] === gruvbox[p]);
        });

        // ============ Part B: geometry invariance ============
        // Every pair below is the SAME widget/screen, constructed with the
        // SAME non-theme props, differing only in which palette object it
        // was handed. Any inequality here means something that should
        // have been a widget default leaked into the palette (or the
        // reverse) -- see this file's own header.
        eq("XpButton.implicitWidth unchanged", btnL.implicitWidth, btnG.implicitWidth);
        eq("XpButton.implicitHeight unchanged", btnL.implicitHeight, btnG.implicitHeight);

        eq("XpTextField.implicitWidth unchanged", fieldL.implicitWidth, fieldG.implicitWidth);
        eq("XpTextField.implicitHeight unchanged", fieldL.implicitHeight, fieldG.implicitHeight);

        eq("XpComboBox.implicitWidth unchanged", comboL.implicitWidth, comboG.implicitWidth);
        eq("XpComboBox.implicitHeight unchanged", comboL.implicitHeight, comboG.implicitHeight);
        // Popup height is comboVisibleRows * controlHeight (clamped by
        // contentHeight) -- both inherited, so opening the popup on both
        // must produce the identical height even though comboVisibleRows
        // is exactly the kind of "chrome behavior" property Theme.qml's
        // own boundary comment says a FUTURE palette variant might
        // plausibly want to change (Gruvbox does not).
        comboL.openPopup(); comboG.openPopup();
        ok("XpComboBox popup opened on both", comboL.popupOpen === true && comboG.popupOpen === true);
        eq("XpComboBox popup height unchanged", comboL.height, comboG.height);
        comboL.closePopup(); comboG.closePopup();

        eq("XpBanner.implicitWidth unchanged", bannerL.implicitWidth, bannerG.implicitWidth);
        eq("XpBanner.implicitHeight unchanged", bannerL.implicitHeight, bannerG.implicitHeight);

        eq("XpDialog.implicitWidth unchanged", dialogL.implicitWidth, dialogG.implicitWidth);
        eq("XpDialog.implicitHeight unchanged", dialogL.implicitHeight, dialogG.implicitHeight);

        // --- the real screens, exactly as Skin.qml assembles them ---
        eq("LogonDialog.implicitWidth unchanged", dlgL.implicitWidth, dlgG.implicitWidth);
        eq("LogonDialog.implicitHeight unchanged", dlgL.implicitHeight, dlgG.implicitHeight);
        eq("LogonDialog user row height unchanged", dlgL.testUserRowHeight, dlgG.testUserRowHeight);
        eq("LogonDialog secret row height unchanged", dlgL.testSecretRowHeight, dlgG.testSecretRowHeight);
        eq("LogonDialog status row height unchanged", dlgL.testStatusRowHeight, dlgG.testStatusRowHeight);
        ok("LogonDialog row heights are real (not both zero)", dlgL.testUserRowHeight > 0);

        eq("ShutDownDialog.implicitWidth unchanged", sdL.implicitWidth, sdG.implicitWidth);
        eq("ShutDownDialog.implicitHeight unchanged", sdL.implicitHeight, sdG.implicitHeight);

        // ============ Part C: colors actually differ (rendered) ============
        // Harvested off the live child tree, independent of Part A's
        // object-level comparison -- proves the WIDGET rendering actually
        // consumed the swapped theme, not just that the theme objects
        // themselves differ.
        [
            ["XpButton", btnL, btnG],
            ["XpTextField", fieldL, fieldG],
            ["XpComboBox", comboL, comboG],
            ["XpBanner", bannerL, bannerG],
            ["XpDialog", dialogL, dialogG],
            ["LogonDialog", dlgL, dlgG],
            ["ShutDownDialog", sdL, sdG]
        ].forEach(function (triple) {
            var name = triple[0], a = [], b = [];
            root._harvestColors(triple[1], a);
            root._harvestColors(triple[2], b);
            ok(name + ": harvested at least one color from each instance", a.length > 0 && b.length > 0);
            ok(name + ": same number of colors harvested from both (same tree shape)", a.length === b.length);
            ok(name + ": at least one harvested color differs between luna and gruvbox",
                JSON.stringify(a) !== JSON.stringify(b));
        });

        // ============ Part D: unregistered palette name falls back ============
        // fallbackSkin was constructed against QSG_DEFAULTS'
        // skinSettings.xp.palette = an unregistered string (see this
        // file's fixture comment above) -- Skin.qml's own `theme` binding
        // must resolve that to Luna's values, not `undefined`. Compared
        // against `luna` above by VALUE (object identity would also be a
        // valid proof, but fallbackSkin's own lunaPalette is a distinct
        // instance from this file's `luna`, constructed inside Skin.qml
        // itself) across one representative property from each of the
        // three categories Part A already established: a color (proves
        // the fallback did not resolve to an all-undefined theme), an
        // inherited metric, and the same-value font -- if the fallback
        // silently produced a half-populated object instead of the real
        // Luna instance, at least one of these three would not match.
        ok("Settings actually settled before this check (palette should read back as the unregistered fixture value)",
            XpKit.Settings.ready === true);
        eq("unregistered palette name falls back to luna's values (face)", fallbackSkin.theme.face, luna.face);
        eq("unregistered palette name falls back to luna's values (controlHeight)", fallbackSkin.theme.controlHeight, luna.controlHeight);
        eq("unregistered palette name falls back to luna's values (ui)", fallbackSkin.theme.ui, luna.ui);
        ok("fallback did NOT accidentally land on gruvbox instead", fallbackSkin.theme.face !== gruvbox.face);

        console.log("PALETTE-TEST " + (root.pass === root.total ? "PASS" : "FAIL") + " " + root.pass + "/" + root.total);
        Qt.quit();
    }
}
