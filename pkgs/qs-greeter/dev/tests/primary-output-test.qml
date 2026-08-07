import QtQuick
import Quickshell
import "PrimaryOutput.js" as M

// Headless coverage for the final micro-fix's Item 1: a configured
// primaryOutput that names an output not currently connected must still
// leave exactly one screen holding the keyboard, never none. shell.qml
// itself is PanelWindow-rooted and not testable under offscreen QPA (no
// backend loaded at all -- see this plan's own note on that), so this
// drives PrimaryOutput.js directly, the same "pull the decision into pure
// JS" shape SettingsMerge.js already uses for the same reason -- this is
// the REAL file shell.qml imports (same-directory symlink, mode 120000),
// not a copy.
ShellRoot {
    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (got === want) pass++;
            else console.log("PRIMARY-OUTPUT-TEST CASE FAIL: " + name
                + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
        }

        var eDP1 = { name: "eDP-1" };
        var dp1 = { name: "DP-1" };
        var screens = [eDP1, dp1];

        // unset name: falls back to screens[0], exactly one claimant
        check("unsetPicksFirst_eDP1", M.isPrimary(screens, "", eDP1), true);
        check("unsetPicksFirst_dp1", M.isPrimary(screens, "", dp1), false);

        // present name: that screen wins, not screens[0]
        check("presentNameWins_dp1", M.isPrimary(screens, "DP-1", dp1), true);
        check("presentNameWins_eDP1", M.isPrimary(screens, "DP-1", eDP1), false);

        // --- the core assertion this item is about: a name that matches
        // NOTHING currently connected (set while docked, then undocked)
        // must degrade to the screens[0] rule, not to "nothing matches".
        // Checked positively (screens[0] claims it) AND as a coverage
        // count across the whole list (exactly one screen claims it, never
        // zero) so a regression back to the old bare `screen.name ===
        // name` comparison -- which would make every entry below false --
        // cannot slip past by accident. ---
        var missing = "eDP-99-not-connected";
        check("absentNameFallsBackToFirst_eDP1", M.isPrimary(screens, missing, eDP1), true);
        check("absentNameFallsBackToFirst_dp1", M.isPrimary(screens, missing, dp1), false);
        var claimants = screens.filter(function (s) { return M.isPrimary(screens, missing, s); });
        check("absentNameLeavesExactlyOneClaimant", claimants.length, 1);

        // empty screens list: no claimant is possible, must not throw
        check("emptyScreensNoClaimant", M.isPrimary([], "eDP-1", eDP1), false);

        // null screen: never a claimant
        check("nullScreenNeverClaims", M.isPrimary(screens, "DP-1", null), false);

        console.log("PRIMARY-OUTPUT-TEST " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
        Qt.quit();
    }
}
