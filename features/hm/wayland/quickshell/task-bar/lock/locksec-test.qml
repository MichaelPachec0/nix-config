// features/hm/wayland/quickshell/task-bar/lock/locksec-test.qml
// Unit test for LockSecurity's row-visibility rules and uptime formatting. Run:
//   quickshell -p features/hm/wayland/quickshell/task-bar/lock/locksec-test.qml
// Expect a single "SEC-TEST PASS n/n" line.
//
// Sibling of the component on purpose: qs -p sandboxes imports to the
// entrypoint's parent directory, so `import "../"` is blocked and a bare type
// name is the only way to resolve LockSecurity (same as notiffit-test.qml).
import QtQuick
import Quickshell

ShellRoot {
    LockSecurity {
        id: sec
        theme: null
        stampFn: function (nowMs, thenMs, use12h) {
            return thenMs > 0 ? "STAMP" : "";
        }
    }

    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (got === want) pass++;
            else console.log("SEC-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
        }

        // ---- sharing / unknown ------------------------------------------
        // A capture running when the lock engaged always counts, whatever the
        // poll later says.
        sec.probed = true;
        sec.pollEnabled = true; sec.castAtLock = true; sec.casts = 0;
        check("share/atLock", sec.sharing, true);
        check("share/atLock-noUnknown", sec.sharingUnknown, false);

        // The poll finding a capture counts too.
        sec.castAtLock = false; sec.casts = 2;
        check("share/poll", sec.sharing, true);

        // 0 means "asked, nothing capturing" -- NOT unknown.
        sec.casts = 0;
        check("share/zero", sec.sharing, false);
        check("share/zero-noUnknown", sec.sharingUnknown, false);

        // null means "could not ask" -> the warning row.
        sec.casts = null;
        check("share/null", sec.sharing, false);
        check("share/null-unknown", sec.sharingUnknown, true);

        // Unknown never competes with an actual detection.
        sec.castAtLock = true;
        check("share/null-butAtLock", sec.sharingUnknown, false);
        sec.castAtLock = false;

        // With the poll switched off, casts is permanently null -- the warning
        // must NOT latch on, or opting out becomes a permanent false alarm.
        sec.pollEnabled = false;
        check("share/pollOff-noUnknown", sec.sharingUnknown, false);
        sec.pollEnabled = true;

        // Before the first probe result, "unknown" must stay silent -- otherwise
        // it would flash on every lock and train the user to ignore it.
        sec.probed = false; sec.pollEnabled = true; sec.casts = null; sec.castAtLock = false;
        check("share/unprobed-silent", sec.sharingUnknown, false);
        sec.probed = true;
        check("share/probed-unknown", sec.sharingUnknown, true);

        // ---- uptime formatting ------------------------------------------
        check("up/0", sec._fmtUptime(0), "just booted");
        check("up/59s", sec._fmtUptime(59), "just booted");
        check("up/60s", sec._fmtUptime(60), "1m");
        check("up/59m", sec._fmtUptime(59 * 60), "59m");
        check("up/1h", sec._fmtUptime(3600), "1h 0m");
        check("up/90m", sec._fmtUptime(90 * 60), "1h 30m");
        check("up/23h", sec._fmtUptime(23 * 3600 + 59 * 60), "23h 59m");
        check("up/1d", sec._fmtUptime(86400), "1d 0h");
        check("up/2d22h", sec._fmtUptime(2 * 86400 + 22 * 3600), "2d 22h");

        // ---- last unlock -------------------------------------------------
        sec.lastUnlockMs = 0;
        check("unlock/never", sec.lastUnlockText, "Last unlock unknown");
        sec.lastUnlockMs = 1000;
        check("unlock/known", sec.lastUnlockText, "Last unlock STAMP");

        // ---- plurals -----------------------------------------------------
        check("plural/1fail", sec._failText(1), "1 failed attempt");
        check("plural/2fail", sec._failText(2), "2 failed attempts");
        check("plural/1sess", sec._sessionText(1), "1 other session");
        check("plural/2sess", sec._sessionText(2), "2 other sessions");

        console.log(pass === total ? ("SEC-TEST PASS " + pass + "/" + total)
                                   : ("SEC-TEST FAIL " + pass + "/" + total));
        Qt.quit();
    }
}
