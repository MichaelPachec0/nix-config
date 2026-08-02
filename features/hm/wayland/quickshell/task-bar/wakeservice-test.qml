// Headless check for lib/WakeService.qml. Run:
//     quickshell -p wakeservice-test.qml
//
// Drives a fixture stamp through the states the real /run/qs-wake/stamp goes
// through and asserts when woke() may fire. Getting this wrong is expensive in
// both directions: a missed wake leaves the bar showing the previous city, and
// a spurious one costs a geoclue fix plus an API call every few seconds.
//
// Lives at the config ROOT because `quickshell -p` makes the entrypoint's
// parent the root, and lib/ must stay inside it.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib" as Lib

ShellRoot {
    id: harness

    // The fixture is seeded by the runner BEFORE quickshell starts, so the
    // service's first read sees an existing stamp -- which is exactly the
    // shell-started-after-a-resume case that must NOT report a wake.
    property string fixture: Quickshell.env("WAKE_FIXTURE")

    property int wokeCount: 0
    property int pass: 0
    property int fail: 0
    property int step: 0

    function check(name, cond, detail) {
        if (cond) { harness.pass++; console.log("  ok   " + name + "   " + (detail || "")); }
        else { harness.fail++; console.log("  FAIL " + name + "   " + (detail || "")); }
    }

    Lib.WakeService {
        id: wake
        stampPath: harness.fixture
    }

    Connections {
        target: wake
        function onWoke() { harness.wokeCount++; }
    }

    Process { id: writer }
    function write(text) {
        // printf via sh, mirroring the hook's write-then-rename so the test
        // exercises the same inode-replacement the watch has to survive.
        writer.exec(["sh", "-c",
            "printf '%s\\n' '" + text + "' > '" + harness.fixture + ".tmp' && "
            + "mv -f '" + harness.fixture + ".tmp' '" + harness.fixture + "'"]);
    }

    Timer {
        interval: 2500
        repeat: true
        running: true
        onTriggered: {
            harness.step++;
            switch (harness.step) {
            case 1:
                harness.check("startup read of an existing stamp is not a wake",
                              harness.wokeCount === 0, "woke=" + harness.wokeCount);
                harness.check("the stamp value is picked up regardless",
                              wake.stamp === 1000, "stamp=" + wake.stamp);
                harness.write("2000");
                break;
            case 2:
                harness.check("a new stamp fires woke exactly once",
                              harness.wokeCount === 1, "woke=" + harness.wokeCount);
                harness.check("stamp advanced", wake.stamp === 2000, "stamp=" + wake.stamp);
                harness.write("2000");
                break;
            case 3:
                harness.check("re-reading the same stamp does not re-fire",
                              harness.wokeCount === 1, "woke=" + harness.wokeCount);
                harness.write("not-a-number");
                break;
            case 4:
                harness.check("junk is ignored rather than treated as a wake",
                              harness.wokeCount === 1, "woke=" + harness.wokeCount);
                harness.check("junk does not clobber the last good stamp",
                              wake.stamp === 2000, "stamp=" + wake.stamp);
                harness.write("3000");
                break;
            case 5:
                harness.check("a later wake fires again",
                              harness.wokeCount === 2, "woke=" + harness.wokeCount);
                console.log("WAKE-QML " + harness.pass + "/" + (harness.pass + harness.fail));
                Qt.exit(harness.fail === 0 ? 0 : 1);
                break;
            }
        }
    }
}
