// features/hm/wayland/quickshell/task-bar/lib/notiftime-test.qml
// Unit test for notiftime.js. Run headless:
//   quickshell -p features/hm/wayland/quickshell/task-bar/lib/notiftime-test.qml
// Expect a single "TIME-TEST PASS n/n" line.
import QtQuick
import Quickshell
import "notiftime.js" as T

ShellRoot {
    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (got === want) pass++;
            else console.log("TIME-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
        }
        function match(name, got, re) {
            total++;
            if (re.test(got)) pass++;
            else console.log("TIME-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " !~ " + re);
        }

        // A fixed "now": 2026-07-30 14:32:00 local.
        var now = new Date(2026, 6, 30, 14, 32, 0).getTime();
        var MIN = 60000, HOUR = 60 * MIN, DAY = 24 * HOUR;

        // No recorded arrival time -> no stamp at all, never a wrong one.
        check("nostamp/zero", T.fmtStamp(now, 0, false), "");
        check("nostamp/undef", T.fmtStamp(now, undefined, false), "");
        check("nostamp/negative", T.fmtStamp(now, -5, false), "");

        // Relative wording boundaries.
        check("rel/now", T.fmtStamp(now, now, false), "14:32 (just now)");
        check("rel/59s", T.fmtStamp(now, now - 59000, false), "14:31 (just now)");
        check("rel/60s", T.fmtStamp(now, now - 60000, false), "14:31 (1m ago)");
        check("rel/59m", T.fmtStamp(now, now - 59 * MIN, false), "13:33 (59m ago)");
        check("rel/60m", T.fmtStamp(now, now - 60 * MIN, false), "13:32 (1h ago)");
        match("rel/23h", T.fmtStamp(now, now - 23 * HOUR, false), /^[A-Z][a-z]{2} 15:32 \(23h ago\)$/);
        // 24h ago is the previous day -> day prefix + "1d ago".
        match("rel/24h", T.fmtStamp(now, now - 24 * HOUR, false), /^[A-Z][a-z]{2} 14:32 \(1d ago\)$/);
        match("rel/2d", T.fmtStamp(now, now - 2 * DAY, false), /^[A-Z][a-z]{2} 14:32 \(2d ago\)$/);

        // A future stamp (clock skew) must not print a negative age.
        check("rel/future", T.fmtStamp(now, now + 5 * MIN, false), "14:37 (just now)");

        // Same day carries NO day prefix; a different day always does.
        match("prefix/today", T.fmtStamp(now, now - 2 * HOUR, false), /^\d{2}:\d{2} \(/);
        match("prefix/notToday", T.fmtStamp(now, now - 2 * DAY, false), /^[A-Z][a-z]{2} \d{2}:\d{2} \(/);

        // 12h clock shape.
        check("12h/pm", T.fmtStamp(now, now, true), "2:32 PM (just now)");
        var midnight = new Date(2026, 6, 30, 0, 15, 0).getTime();
        check("12h/midnight", T.fmtStamp(midnight + 1000, midnight, true), "12:15 AM (just now)");
        var noon = new Date(2026, 6, 30, 12, 5, 0).getTime();
        check("12h/noon", T.fmtStamp(noon + 1000, noon, true), "12:05 PM (just now)");
        check("24h/midnight", T.fmtStamp(midnight + 1000, midnight, false), "00:15 (just now)");

        console.log(pass === total ? ("TIME-TEST PASS " + pass + "/" + total)
                                  : ("TIME-TEST FAIL " + pass + "/" + total));
        Qt.quit();
    }
}
