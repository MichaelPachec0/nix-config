import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Who is capturing right now: microphone, camera, and screencast, with the
// owning application where it can be determined. Read by the bar's
// CaptureWidget and its DevicePopup. Shell-global -- ONE instance for all
// monitors, like NotifService. A per-monitor copy would multiply the camera
// subprocess by the monitor count (see the NetworkService comment in shell.qml
// for what that cost looks like in practice).
//
// Three sources, because no single one sees everything:
//   mic  -- native PipeWire nodes, event-driven, free
//   cast -- Hyprland's screencast refcount, event-driven, free
//   cam  -- a /proc fd scan, the only pollable one
//
// PwNode has NO `state` property (members are exactly objectName, id, name,
// description, nickname, isSink, isStream, type, properties, audio, ready), so
// node PRESENCE is the liveness test. A Stream/Input/Audio node appears and
// vanishes with the stream. A corked-but-open stream therefore counts as
// active, which over-reports in the safe direction for a privacy indicator.
QtObject {
    id: svc

    // --- inputs -----------------------------------------------------------
    property bool locked: false
    // Clearing the reading is not enough on its own: CommandPoll skips
    // updated() when stdout repeats, and the pre-lock output is still its
    // dedup baseline -- so the first post-unlock poll, which normally MATCHES
    // that baseline, would be swallowed and leave `cameras` stuck at null.
    // Dropping the baseline guarantees the resumed poll re-emits. Same hazard
    // lock/Lock.qml gates with secStale, and the same reason `cameras` is
    // seeded null rather than [].
    onLockedChanged: {
        if (svc.locked) {
            svc.cameras = null;
            camPoll.resetDedup();
            svc.camSettled = false;
            svc.castSettled = false;
            return;
        }
        castSettleTimer.restart();
    }

    // Settling flags: gating on `locked` alone still flashed both glyphs on the
    // way OUT of a lock, because the state that made them true outlives the lock
    // by a little. The camera reading was cleared to null on the way in, so it
    // reads "unknown" until the resumed poll answers (~53ms); Hyprland has not
    // yet reported the backdrop's capture as stopped, so the cast still reads
    // active. Both resolve on their own, but not before the bar is back on
    // screen, and Pill's 260ms width animation stretches the blip into a
    // visible wobble.
    //
    // camSettled is exact -- it waits for an actual poll result rather than a
    // duration, the same contract lock/LockSecurity.qml's `probed` uses, and it
    // suppresses ONLY the unknown warning. A real camera still lights up the
    // instant the first poll lands. It starts false so the same rule covers
    // shell startup, where "no answer yet" also is not "unknown".
    property bool camSettled: false
    // Backstop, mirroring LockSecurity's graceExpired. camSettled otherwise
    // waits on a poll result that a missing or broken script never delivers,
    // and a latched-false camSettled would suppress the unknown warning
    // permanently -- silence reading as "camera is idle" is the exact failure
    // this warning exists to prevent. The `running` binding re-arms it at
    // startup and after every unlock, and stops it once a result lands.
    property Timer camGraceTimer: Timer {
        interval: 2500
        running: !svc.locked && !svc.camSettled
        onTriggered: svc.camSettled = true
    }
    // castSettled has no event to wait for, so it is a duration. Hyprland
    // derives sharing from frame delivery with a ~500ms idle timeout, so the
    // stop can trail teardown by that much; 600ms clears it with margin.
    // Starts TRUE so a shell start with no lock in sight is not suppressed.
    //
    // The trade this makes: a screen share that was genuinely running across
    // the lock stays hidden for those 600ms after unlock. Accepted because the
    // opposite error is worse for this indicator -- a glyph that cries wolf on
    // every single unlock is one the user learns to ignore, and the lock's own
    // security column already reported sharing state moments earlier.
    property bool castSettled: true
    property Timer castSettleTimer: Timer {
        interval: 600
        onTriggered: svc.castSettled = true
    }
    property int castCount: 0
    property string castOwner: ""
    property string castTarget: ""

    readonly property var allNodes: Pipewire.nodes.values || []
    // Without this tracker `properties` stays unpopulated and every derived
    // list silently reads empty.
    property PwObjectTracker tracker: PwObjectTracker {
        objects: svc.allNodes
    }

    // --- pure derivations (fixture-tested by capture-test.qml) -------------
    // media.class is compared with === and never contains(): a paired
    // Bluetooth headset in HFP/SCO keeps Stream/Input/Audio/Internal and
    // Audio/Source/Internal present with nothing capturing, so a substring
    // match pins the mic glyph on for as long as the headset is connected.
    function micsFromNodes(list) {
        var out = [];
        var ns = list || [];
        for (var i = 0; i < ns.length; i++) {
            var p = (ns[i] && ns[i].properties) ? ns[i].properties : {};
            if (String(p["media.class"] || "") !== "Stream/Input/Audio")
                continue;
            var bin = String(p["application.process.binary"] || "");
            // The PipeWire global id, carried through so the popup can tell two
            // rows apart. One process can hold TWO mic streams at once (two
            // browser tabs in calls), and those rows are identical in every
            // other field -- including pid, which is what the popup's arm/kill
            // gesture used to key on. Two rows sharing an arm key meant clicking
            // one armed both, so the next click on the other sent TERM with no
            // confirmation. Falls back to the index only for fixtures; a real
            // PwNode always carries an id.
            var nid = (ns[i] && ns[i].id !== undefined && ns[i].id !== null) ? ns[i].id : ("i" + i);
            out.push({
                nodeId: nid,
                pid: parseInt(p["application.process.id"], 10) || null,
                appName: String(p["application.name"] || "") || bin || "unknown",
                binary: bin
            });
        }
        return out;
    }

    // One row per active cast. A cast with no PipeWire consumer still gets a
    // row (wlr-screencopy tools such as wf-recorder create no node at all),
    // but with pid null so DevicePopup renders no kill button -- killing a
    // guessed pid is unrecoverable if wrong.
    function castsFrom(count, owner, target, list) {
        if (!(count > 0))
            return [];
        var consumer = null;
        var ns = list || [];
        for (var i = 0; i < ns.length && !consumer; i++) {
            var p = (ns[i] && ns[i].properties) ? ns[i].properties : {};
            if (String(p["media.class"] || "") === "Stream/Input/Video")
                consumer = p;
        }
        var bin = consumer ? String(consumer["application.process.binary"] || "") : "";
        return [{
            owner: String(owner || ""),
            target: String(target || ""),
            pid: consumer ? (parseInt(consumer["application.process.id"], 10) || null) : null,
            appName: consumer ? (String(consumer["application.name"] || "") || bin || "unknown") : ""
        }];
    }

    // --- derived state ----------------------------------------------------
    readonly property var mics: svc.micsFromNodes(svc.allNodes)
    readonly property var casts: svc.castsFrom(svc.castCount, svc.castOwner, svc.castTarget, svc.allNodes)

    // null = the scan could not run; [] = it ran and found nothing. Seeded null
    // so the first frames before any poll result read as "not yet known"
    // rather than as a false all-clear.
    property var cameras: null

    // Every visible signal is gated on `locked`, not merely the camera poll.
    // Two separate flashes come out of the lock itself, both on a bar the user
    // is about to stop seeing: the lock's own backdrop ScreencopyView counts as
    // a screencast to Hyprland (so castActive goes true), and clearing the stale
    // camera reading makes cameraUnknown go true. Gating only the poll left both
    // of them on screen for the 25-250ms the desktop is still composited.
    // The lock draws its own security column; the bar reports the DESKTOP.
    readonly property bool micActive: !svc.locked && (svc.mics || []).length > 0
    readonly property bool castActive: !svc.locked && svc.castSettled && (svc.casts || []).length > 0
    readonly property bool cameraActive: !svc.locked && svc.cameras !== null && svc.cameras.length > 0
    readonly property bool cameraUnknown: !svc.locked && svc.camSettled && svc.cameras === null
    // cameraUnknown counts as "something to show": the pill must stay clickable
    // and visibly uncertain rather than silently claiming the camera is idle.
    readonly property bool anyActive: svc.micActive || svc.castActive
        || svc.cameraActive || svc.cameraUnknown

    // --- camera poll ------------------------------------------------------
    // Stopped while locked: the lock runs its own 10s probe
    // (lib/lock-security-probe.sh) and the bar is not visible anyway, so
    // polling here would be pure duplicate cost.
    property CommandPoll camPoll: CommandPoll {
        interval: 3000
        running: !svc.locked
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/capture-devices.sh"]
        parse: function (out) {
            try {
                var o = JSON.parse(String(out));
                return (o.cameras === null || o.cameras === undefined) ? null : o.cameras;
            } catch (e) {
                return null;
            }
        }
        onUpdated: {
            // A Process already in flight when the lock landed still exits and
            // emits here, AFTER resetDedup() ran. Taking its value would undo
            // the clear, and simply ignoring it would leave it as the dedup
            // baseline that the first post-unlock poll matches byte-for-byte --
            // which is exactly the permanent-"unknown" strand a previous fix
            // round removed. Drop the baseline again so the resumed poll is
            // guaranteed to emit.
            if (svc.locked) {
                camPoll.resetDedup();
                return;
            }
            svc.cameras = camPoll.value;
            // A result landed, so null now means "unknown" rather than "not
            // asked yet" and the warning glyph is allowed to speak.
            svc.camSettled = true;
        }
    }
}
