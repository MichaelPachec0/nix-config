import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Who is capturing right now: microphone, camera, and screencast, with the
// owning application where it can be determined. Read by the bar's media pill
// and its DevicePopup. Shell-global -- ONE instance for all monitors, like
// NotifService. A per-monitor copy would multiply the camera subprocess by the
// monitor count (see the NetworkService comment in shell.qml for what that
// cost looks like in practice).
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
    // Lib.CommandPoll does NOT clear `value` when `running` goes false->true,
    // so without this the first moments after unlock would render the reading
    // captured BEFORE the lock as if it were current -- a false "no camera in
    // use" at exactly the moment the bar becomes visible again. Same hazard
    // lock/Lock.qml gates with secStale, and the same reason `cameras` is
    // seeded null rather than [].
    onLockedChanged: if (svc.locked) svc.cameras = null
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
            out.push({
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

    readonly property bool micActive: (svc.mics || []).length > 0
    readonly property bool castActive: (svc.casts || []).length > 0
    readonly property bool cameraActive: svc.cameras !== null && svc.cameras.length > 0
    readonly property bool cameraUnknown: svc.cameras === null
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
        onUpdated: svc.cameras = camPoll.value
    }
}
