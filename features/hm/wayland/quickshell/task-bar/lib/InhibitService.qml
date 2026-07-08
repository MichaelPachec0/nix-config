pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "inhibitlogic.js" as InhibitLogic

// Shared "stay awake" state for the two bar icons + the popup: two concerns
// (idle = Wayland idle-inhibit; sleep = logind block inhibitor), each off /
// on-indefinite / on-timed, plus a lock that couples them. Persisted across
// restarts via the repo's FileView+JsonAdapter idiom (see lib/CalState.qml),
// stored as flat scalars. The window-free systemd-inhibit Process lives here;
// the window-bound IdleInhibitor lives in AwakeCluster. now ticks every second
// so countdown bindings update. Instantiated once (AwakeCluster) and passed by
// reference -- mirrors NetworkService/AudioService.
Scope {
    id: svc

    // --- reactive state (aliases onto the persisted adapter) ---
    property alias idleOn: adapter.idleOn
    property alias idleExpiry: adapter.idleExpiry
    property alias sleepOn: adapter.sleepOn
    property alias sleepExpiry: adapter.sleepExpiry
    property alias locked: adapter.locked
    property alias lastDurationMs: adapter.lastDurationMs
    property alias idleDefaultMs: adapter.idleDefaultMs
    property alias sleepDefaultMs: adapter.sleepDefaultMs

    property double now: Date.now()

    readonly property var presets: [900000, 1800000, 3600000, 7200000, 14400000, 0]

    readonly property string _stateDir: (Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"

    // --- flat<->nested bridge for the pure logic ---
    function _snapshot() {
        return {
            idle: {
                on: svc.idleOn,
                expiry: svc.idleExpiry
            },
            sleep: {
                on: svc.sleepOn,
                expiry: svc.sleepExpiry
            },
            locked: svc.locked,
            lastDurationMs: svc.lastDurationMs,
            idleDefaultMs: svc.idleDefaultMs,
            sleepDefaultMs: svc.sleepDefaultMs
        };
    }
    function _write(s) {
        // Assigning adapter props triggers onAdapterUpdated -> writeAdapter().
        adapter.idleOn = s.idle.on;
        adapter.idleExpiry = s.idle.expiry;
        adapter.sleepOn = s.sleep.on;
        adapter.sleepExpiry = s.sleep.expiry;
        adapter.locked = s.locked;
        adapter.lastDurationMs = s.lastDurationMs;
        adapter.idleDefaultMs = s.idleDefaultMs;
        adapter.sleepDefaultMs = s.sleepDefaultMs;
    }

    // --- commands ---
    function _setConcern(s, which, on, expiry) {
        s[which].on = on;
        s[which].expiry = expiry;
        if (s.locked) {
            var other = which === "idle" ? "sleep" : "idle";
            s[other].on = on;
            s[other].expiry = expiry;
        }
        return s;
    }
    function defaultMs(which) {
        return which === "idle" ? svc.idleDefaultMs : svc.sleepDefaultMs;
    }
    function setDefault(which, ms) {
        if (which === "idle")
            adapter.idleDefaultMs = ms;
        else
            adapter.sleepDefaultMs = ms;
    }
    // Turn a concern on for its default duration (indefinite when default is 0),
    // or off. Used by the popup switch and the bar icons.
    function toggle(which) {
        var on = which === "idle" ? svc.idleOn : svc.sleepOn;
        if (on)
            svc.disarm(which);
        else
            svc.arm(which, svc.defaultMs(which));
    }
    function arm(which, ms) {
        var s = svc._snapshot();
        s.lastDurationMs = ms;
        var expiry = ms > 0 ? (Date.now() + ms) : 0;
        svc._write(svc._setConcern(s, which, true, expiry));
    }
    function disarm(which) {
        var s = svc._snapshot();
        svc._write(svc._setConcern(s, which, false, 0));
    }
    function extend(which, ms) {
        var s = svc._snapshot();
        if (!s[which].on || s[which].expiry === 0)
            return; // only timed extends
        var e = s[which].expiry + ms;
        svc._write(svc._setConcern(s, which, true, e));
    }
    function setLocked(on) {
        var s = svc._snapshot();
        svc._write(on ? InhibitLogic.applyLock(s) : InhibitLogic.applyUnlock(s));
    }

    // --- derived (used by the bar timers + popup) ---
    function isIndefinite(which) {
        return which === "idle" ? (svc.idleOn && svc.idleExpiry === 0) : (svc.sleepOn && svc.sleepExpiry === 0);
    }
    function remainingMs(which) {
        var on = which === "idle" ? svc.idleOn : svc.sleepOn;
        var exp = which === "idle" ? svc.idleExpiry : svc.sleepExpiry;
        if (!on || exp === 0)
            return 0;
        return Math.max(0, exp - svc.now);
    }
    function countdownText(which) {
        var on = which === "idle" ? svc.idleOn : svc.sleepOn;
        if (!on)
            return "";
        if (svc.isIndefinite(which))
            return InhibitLogic.infinityGlyph();
        return InhibitLogic.formatCountdown(svc.remainingMs(which));
    }

    // --- 1s tick: advance now + auto-release elapsed timers ---
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            svc.now = Date.now();
            if (svc.idleOn && svc.idleExpiry > 0 && svc.now >= svc.idleExpiry)
                svc.disarm("idle");
            if (svc.sleepOn && svc.sleepExpiry > 0 && svc.now >= svc.sleepExpiry)
                svc.disarm("sleep");
        }
    }

    // --- sleep engagement: logind block inhibitor (window-free) ---
    // Held exactly as long as this process runs; SIGTERM on running=false
    // releases it. sleep + handle-lid-switch so lid-close is also covered.
    Process {
        running: svc.sleepOn
        command: ["systemd-inhibit", "--what=sleep:handle-lid-switch", "--who=Quickshell", "--why=Stay awake toggle", "--mode=block", "sleep", "infinity"]
    }

    // --- persistence (CalState idiom) ---
    Process {
        running: true
        command: ["mkdir", "-p", svc._stateDir]
    }
    FileView {
        id: file
        path: svc._stateDir + "/inhibit-state.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            // Expire anything that elapsed while we were gone, and persist the
            // corrected state back.
            var s = InhibitLogic.reconcileOnLoad(svc._snapshot(), Date.now());
            svc._write(s);
        }
        Component.onCompleted: reload()

        JsonAdapter {
            id: adapter
            property bool idleOn: false
            property real idleExpiry: 0
            property bool sleepOn: false
            property real sleepExpiry: 0
            property bool locked: false
            property real lastDurationMs: 3600000
            property real idleDefaultMs: 0
            property real sleepDefaultMs: 0
        }
    }
}
