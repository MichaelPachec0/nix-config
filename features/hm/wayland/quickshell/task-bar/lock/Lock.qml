// features/hm/wayland/quickshell/task-bar/lock/Lock.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../lib" as Lib
import "../lib/locations.js" as Locations

Scope {
    id: root

    property bool locked: false
    property alias context: lockContext
    property var wallpapers: ({}) // screenName -> image path
    readonly property var weather: weatherPoll.value // {temp, icon, desc, uv, conditions[], ...} or null
    property var audio: null // Lib.AudioService, threaded from shell.qml

    // Drives the surfaces' blur/content animation. Set false while the surface
    // is still up so the unlock detransition can play before the compositor
    // lock is released.
    property bool revealed: false

    // A lock request always wins over an in-flight unlock detransition. Note
    // `root.locked = true` is a no-op when we are already locked (mid-
    // detransition), so onLockedChanged would not fire -- re-arm the reveal
    // and redo the lock-time resets here explicitly, or the surface stays
    // fully transparent AND keeps the just-authenticated password buffer.
    //
    // Wallpaper mode then locks immediately (unchanged MVP behaviour).
    // Workspace mode arms the capture pool and defers `locked` until every
    // output's frame has landed (or captureTimer's 50ms safety net fires).
    function lock() {
        unlockTimer.stop();
        if (root.locked) {
            lockContext.reset();
            root.refreshWallpapers();
            revealTimer.restart();
            return;
        }
        if (!root.workspaceMode) {
            root.locked = true;
            return;
        }
        root.captureArmed = true;
        captureTimer.restart();
    }

    // Unlock is a two-phase move: play the detransition, then release. The
    // Timer -- not any animation signal -- is the authority, so a skipped or
    // broken animation can never strand the session locked.
    function unlock() { root.beginUnlock(); }

    function beginUnlock() {
        if (!root.locked)
            return;
        revealTimer.stop();      // a pending reveal must not fight the detransition
        root.revealed = false;   // starts the blur-out + content fade
        unlockTimer.restart();
    }

    function _release() {
        root.locked = false;                                   // release the compositor lock
        unlockSessionProc.exec(["loginctl", "unlock-session"]); // fire unlock.target
        lockContext.reset();
    }

    function wallpaperFor(name) {
        return (name && root.wallpapers[name]) ? root.wallpapers[name] : LockConfig.fallbackImage;
    }

    function refreshWallpapers() { awwwProc.running = true; }

    LockContext {
        id: lockContext
        // PAM success is still the ONLY thing that reaches here; it now starts
        // the detransition instead of releasing immediately (unlockTimer does
        // the release ~200ms later).
        onUnlocked: root.beginUnlock()
    }
    Process { id: unlockSessionProc }

    // Authoritative unlock release. Matches LockSurface's 200ms blur-out.
    Timer {
        id: unlockTimer
        interval: 200
        onTriggered: root._release()
    }

    LockClockState { id: lockClockState }

    // Bar-mirrored weather poll for the current ("geo") location. Gated to
    // `root.locked` so it only fetches while the lock is up (no always-on
    // network poll); triggeredOnStart in Lib.CommandPoll's Timer means it also
    // fires immediately when the lock engages. command/parse copied verbatim
    // from desktop/WeatherWidget.qml.
    Lib.CommandPoll {
        id: weatherPoll
        interval: 1800000 // 30 min; weather.sh caches the same window
        running: root.locked
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/weather.sh"].concat(Locations.argsArrayFor(Locations.byId("geo")))
        parse: function (out) {
            try {
                var d = JSON.parse(String(out));
                return {
                    temp: d.temp ?? "--",
                    icon: d.icon ?? "cloudy",
                    desc: d.desc ?? "Unknown",
                    source: d.source ?? "",
                    feels: d.feels ?? "",
                    humidity: d.humidity ?? "",
                    precip: d.precip ?? "",
                    wind: d.wind ?? "",
                    windDir: d.windDir ?? "",
                    place: d.place ?? "",
                    forecast: d.forecast ?? [],
                    hourly: d.hourly ?? [],
                    uv: d.uv ?? "",
                    windGust: d.windGust ?? "",
                    precipType: d.precipType ?? "",
                    sunrise: d.sunrise ?? "",
                    sunset: d.sunset ?? "",
                    alerts: d.alerts ?? [],
                    conditions: d.conditions ?? [],
                    nowcast: d.nowcast ?? ({ rainSoon: false, etaMin: null, source: "none", text: "" })
                };
            } catch (e) {
                return null;
            }
        }
    }

    // Per-output desktop capture pool. MUST live here (a sibling of
    // WlSessionLock), not inside the lock surface: Hyprland stops compositing
    // the desktop the moment the lock request lands, which is before any
    // WlSessionLockSurface exists -- a capture started there would grab black.
    // `live: false` latches one frame, so it survives the desktop going dark.
    // Armed only for the duration of a lock; disarming destroys the views and
    // frees their GPU buffers. The frame never leaves the GPU swapchain.
    property bool captureArmed: false

    readonly property bool workspaceMode: LockConfig.backdropMode === "workspace"

    Instantiator {
        id: capturePool
        model: root.captureArmed ? Quickshell.screens : []
        delegate: ScreencopyView {
            required property var modelData
            // True only when the frame landed BEFORE the compositor lock
            // engaged. `hasContent` alone is not enough: it means "a frame
            // arrived", not "a useful frame arrived" -- a copy still in flight
            // when captureTimer locks will latch the post-lock (black) screen
            // and set hasContent true anyway.
            property bool preLockContent: false
            live: false
            captureSource: modelData
            onHasContentChanged: {
                if (hasContent && !root.locked)
                    preLockContent = true;
                root._noteCapture();
            }
        }
    }

    // The ScreencopyView for `screenName`, or null. Evaluated once per surface
    // at creation -- correct because every capture is issued before locked
    // flips, so the pool is already populated by the time surfaces exist.
    function captureFor(screenName) {
        for (var i = 0; i < capturePool.count; i++) {
            var v = capturePool.objectAt(i);
            if (v && v.modelData && v.modelData.name === screenName)
                return v;
        }
        return null;
    }

    function _allCaptured() {
        // The count check is load-bearing on multi-monitor: Instantiator builds
        // its delegates one at a time, so without it the first screen's
        // hasContent could satisfy the loop while the second view does not yet
        // exist -- locking with only one output captured.
        var want = (Quickshell.screens || []).length;
        if (want === 0 || capturePool.count !== want)
            return false;
        for (var i = 0; i < capturePool.count; i++) {
            var v = capturePool.objectAt(i);
            if (!v || !v.preLockContent)
                return false;
        }
        return true;
    }

    // Every capture landed -> stop waiting and lock immediately.
    function _noteCapture() {
        if (root.captureArmed && !root.locked && root._allCaptured()) {
            captureTimer.stop();
            root.locked = true;
        }
    }

    // Safety net: lock even if a capture never lands. The backdrop falls back
    // to the wallpaper Image, so a failed capture costs a blur source, never
    // the lock itself.
    Timer {
        id: captureTimer
        interval: 50
        onTriggered: root.locked = true
    }

    WlSessionLock {
        id: sessionLock
        locked: root.locked

        // One WlSessionLockSurface is created per output automatically.
        surface: WlSessionLockSurface {
            id: surface
            color: "transparent"

            LockSurface {
                anchors.fill: parent
                context: root.context
                backdropSource: root.wallpaperFor(surface.screen ? surface.screen.name : "")
                capture: root.captureFor(surface.screen ? surface.screen.name : "")
                clockState: lockClockState
                weather: root.weather
                audio: root.audio
                revealed: root.revealed
            }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
        function unlock(): void { root.unlock(); }
        function toggle(): void { if (root.locked) root.unlock(); else root.lock(); }
    }

    // Dev escape: when relaunched by lock-escape.sh (QS_LOCK_ESCAPE=1) and
    // fail-open is enabled, acquire the (stranded) lock then immediately release
    // it, which unlocks the compositor. Requires misc:allow_session_lock_restore.
    Component.onCompleted: {
        if (Quickshell.env("QS_LOCK_ESCAPE") === "1" && LockConfig.failOpenOnCrash) {
            root.locked = true;   // re-acquires the stranded lock (restore)
            releaseTimer.start();
        }
    }
    Timer {
        id: releaseTimer
        interval: 200
        onTriggered: root.locked = false; // unlock_and_destroy -> desktop returns
    }

    // Marker file for the watchdog (qs-lock-watchdog): present while locked, so
    // a poll can tell "locked marker present but quickshell dead" apart from a
    // clean unlocked state. NB: single onLockedChanged handler -- later tasks
    // add more effects here rather than declaring a second one.
    onLockedChanged: {
        markerProc.exec(
            root.locked
            ? ["sh", "-c", "touch \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lock.locked\""]
            : ["sh", "-c", "rm -f \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lock.locked\""]
        );
        if (root.locked) {
            lockContext.reset();
            root.refreshWallpapers();
            revealTimer.restart();  // flip `revealed` after the surface exists
        } else {
            root.revealed = false;
            root.captureArmed = false;  // destroys the views, frees the GPU buffers
        }
    }

    Process { id: markerProc }

    // `revealed` must change AFTER the surfaces are built, otherwise the
    // Behaviors see their target as the initial value and no animation plays.
    Timer {
        id: revealTimer
        interval: 16
        onTriggered: root.revealed = true
    }

    // Per-output current wallpaper (LockBackdrop). Refreshed on lock so the
    // backdrop refines from the fallback image to the real wallpaper without
    // any desktop-visible race (locked is already true by then).
    Process {
        id: awwwProc
        command: ["awww", "query"]
        stdout: StdioCollector {
            id: awwwOut
            onStreamFinished: {
                var map = {};
                var re = /^:?\s*(\S+):.*currently displaying:\s*image:\s*(.+)$/;
                var lines = (awwwOut.text || "").split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var m = lines[i].match(re);
                    if (m) map[m[1]] = m[2].trim();
                }
                root.wallpapers = map;
            }
        }
    }
}
