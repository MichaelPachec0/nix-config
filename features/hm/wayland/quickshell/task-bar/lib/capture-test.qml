// features/hm/wayland/quickshell/task-bar/lib/capture-test.qml
// Unit test for CaptureService's pure derivation functions. Run:
//   quickshell -p features/hm/wayland/quickshell/task-bar/lib/capture-test.qml
// Expect a single "CAP-TEST PASS n/n" line.
//
// Sibling of the component on purpose: qs -p sandboxes imports to the
// entrypoint's parent directory, so a bare type name is the only way to
// resolve CaptureService (same as lock/locksec-test.qml).
import QtQuick
import Quickshell

ShellRoot {
    CaptureService {
        id: cap
    }

    // Not started (running: false) -- exists only so the resetDedup() test
    // below can exercise CommandPoll's dedup fields directly without spawning
    // a process.
    CommandPoll {
        id: pollProbe
        running: false
    }

    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (got === want) pass++;
            else console.log("CAP-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
        }

        // `id` mirrors PwNode.id (the PipeWire global id). Omitted by most
        // fixtures on purpose, so the index fallback stays covered too.
        function node(mc, app, bin, pid, id) {
            return {
                id: id,
                properties: {
                    "media.class": mc,
                    "application.name": app,
                    "application.process.binary": bin,
                    "application.process.id": pid
                }
            };
        }

        // ---- the headset trap --------------------------------------------
        // A paired Bluetooth headset in HFP/SCO mode keeps these two nodes
        // present with NOTHING capturing. A contains()/indexOf() match would
        // pin the mic glyph on for as long as the headset is connected -- a
        // false positive that never clears.
        var trap = [
            node("Stream/Input/Audio/Internal", "", "", 0),
            node("Audio/Source/Internal", "", "", 0)
        ];
        check("mic/headsetTrap", cap.micsFromNodes(trap).length, 0);

        // A real capture is EXACTLY Stream/Input/Audio.
        var real = [node("Stream/Input/Audio", "Firefox", "firefox-bin", 5230)];
        check("mic/real-count", cap.micsFromNodes(real).length, 1);
        check("mic/real-app", cap.micsFromNodes(real)[0].appName, "Firefox");
        check("mic/real-pid", cap.micsFromNodes(real)[0].pid, 5230);
        check("mic/real-binary", cap.micsFromNodes(real)[0].binary, "firefox-bin");

        // Trap nodes alongside a real one must not inflate the count.
        check("mic/mixed", cap.micsFromNodes(trap.concat(real)).length, 1);

        // Output streams are not captures.
        check("mic/outputIgnored", cap.micsFromNodes([node("Stream/Output/Audio", "Firefox", "firefox-bin", 5230)]).length, 0);

        // A node with no props must not throw or count.
        check("mic/emptyNode", cap.micsFromNodes([{}]).length, 0);
        check("mic/emptyList", cap.micsFromNodes([]).length, 0);

        // Missing app name falls back to the binary, never to "undefined".
        var noApp = [node("Stream/Input/Audio", "", "obs", 99)];
        check("mic/appFallback", cap.micsFromNodes(noApp)[0].appName, "obs");

        // A node with no process id must yield null, never 0: `kill 0` signals
        // the whole process group, and Task 5 puts a kill button on these rows.
        var noPid = [node("Stream/Input/Audio", "obs", "obs", undefined)];
        check("mic/nullPid", cap.micsFromNodes(noPid)[0].pid, null);

        // ---- per-row identity (the unconfirmed-kill regression) ------------
        // ONE process with TWO mic streams: two browser tabs in calls. The rows
        // are identical in every field including pid, so a pid-keyed arm state
        // armed both at once and the next click on the other row sent TERM with
        // no confirmation. The node id is what keeps them apart.
        var twoTabs = [
            node("Stream/Input/Audio", "Firefox", "firefox-bin", 5230, 61),
            node("Stream/Input/Audio", "Firefox", "firefox-bin", 5230, 62)
        ];
        var tt = cap.micsFromNodes(twoTabs);
        check("mic/sameProcess-count", tt.length, 2);
        check("mic/sameProcess-samePid", tt[0].pid === tt[1].pid, true);
        check("mic/sameProcess-distinctKey", tt[0].nodeId !== tt[1].nodeId, true);
        check("mic/nodeId-fromNode", tt[0].nodeId, 61);

        // Without an id the rows must STILL differ -- falling back to a shared
        // placeholder would recreate the collision the id exists to prevent.
        var noIds = [
            node("Stream/Input/Audio", "Firefox", "firefox-bin", 5230),
            node("Stream/Input/Audio", "Firefox", "firefox-bin", 5230)
        ];
        var ni = cap.micsFromNodes(noIds);
        check("mic/noId-distinctKey", ni[0].nodeId !== ni[1].nodeId, true);

        // ---- casts --------------------------------------------------------
        // No cast -> no rows, whatever the owner/target still say.
        check("cast/none", cap.castsFrom(0, "window", "stale", []).length, 0);

        // A cast with no PipeWire consumer still produces a row -- wlr-screencopy
        // tools (wf-recorder) create no node at all -- but with a null pid, so
        // the popup renders no kill button rather than guessing one.
        var solo = cap.castsFrom(1, "monitor", "", []);
        check("cast/solo-count", solo.length, 1);
        check("cast/solo-pid", solo[0].pid, null);
        check("cast/solo-owner", solo[0].owner, "monitor");

        // With a Stream/Input/Video consumer present, the row gains attribution.
        var consumer = [node("Stream/Input/Video", "Firefox", "firefox-bin", 5230)];
        var attributed = cap.castsFrom(1, "window", "ncspot - GitHub", consumer);
        check("cast/attr-pid", attributed[0].pid, 5230);
        check("cast/attr-app", attributed[0].appName, "Firefox");
        check("cast/attr-target", attributed[0].target, "ncspot - GitHub");

        // ---- unknown vs empty ---------------------------------------------
        // null means "could not ask" and must NOT read as "no camera".
        cap.cameras = null;
        check("cam/null-unknown", cap.cameraUnknown, true);
        check("cam/null-notActive", cap.cameraActive, false);
        check("cam/null-anyActive", cap.anyActive, true);

        // [] means "asked, nothing in use" -- no warning, no glyph.
        cap.cameras = [];
        check("cam/empty-notUnknown", cap.cameraUnknown, false);
        check("cam/empty-notActive", cap.cameraActive, false);

        cap.cameras = [{ device: "/dev/video0", deviceName: "Integrated Camera", pid: 5230, comm: "firefox-devedit", name: "firefox-devedition-bin" }];
        check("cam/present-active", cap.cameraActive, true);
        check("cam/present-notUnknown", cap.cameraUnknown, false);

        // ---- locked gating -------------------------------------------------
        // The lock's own backdrop ScreencopyView registers as a screencast, and
        // the lock also clears the stale camera reading -- so without gating the
        // VISIBLE flags (not merely the poll), every lock flashed a red cast
        // glyph and a yellow unknown-camera glyph on the bar during the
        // 25-250ms the desktop is still composited. The lock draws its own
        // security column; the bar reports the desktop.
        cap.cameras = null; // what the lock's clear leaves behind
        cap.castCount = 1;  // what the backdrop capture looks like
        cap.locked = true;
        check("locked/noCastGlyph", cap.castActive, false);
        check("locked/noCameraUnknown", cap.cameraUnknown, false);
        check("locked/pillHidden", cap.anyActive, false);
        // NO micActive case here on purpose. `mics` derives from the live
        // Pipewire.nodes list, which a fixture cannot inject, so on a machine
        // with nothing recording the assertion holds against the UNGATED
        // implementation too -- it would pass for the wrong reason and cover
        // nothing. micActive carries the identical `!svc.locked &&` gate as the
        // two flags above, which are covered (castCount 1 and cameras null both
        // make the pre-fix code report true).

        // Unlocking must restore the same reading, not latch it off.
        cap.locked = false;
        check("unlocked/castGlyphBack", cap.castActive, true);
        check("unlocked/cameraUnknownBack", cap.cameraUnknown, true);
        cap.castCount = 0;

        // ---- CommandPoll.resetDedup() --------------------------------------
        // Round-2 regression: after a caller discards its value and calls
        // resetDedup(), a repeated stdout must still emit updated(). Without
        // resetDedup the dedup swallows it and the caller stays stuck.
        pollProbe.text = "SAME";
        pollProbe._primed = true;
        pollProbe.resetDedup();
        check("poll/resetDedup-primed", pollProbe._primed, false);
        check("poll/resetDedup-text", pollProbe.text, "");

        console.log(pass === total ? ("CAP-TEST PASS " + pass + "/" + total)
                                   : ("CAP-TEST FAIL " + pass + "/" + total));
        Qt.quit();
    }
}
