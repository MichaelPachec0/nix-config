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
    property var notifications: null // Lib.NotifService, threaded from shell.qml

    // Drives the surfaces' blur/content animation. Set false while the surface
    // is still up so the unlock detransition can play before the compositor
    // lock is released.
    property bool revealed: false

    // Global hide-all panic toggle for locked notifications. Hoisted here
    // (rather than living per-output on LockNotifications) so ONE eye click
    // on any monitor hides sensitive content on EVERY locked output --
    // mirrored/multi-monitor setups must not leave other screens exposed.
    // Reset to false on every lock (see onLockedChanged below); tighten-only,
    // same as before.
    property bool notifHideAll: false

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
        captureTimer.start();
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

    // Lock-only notification classifier; rules are bound to LockConfig so they
    // stay in sync with the Nix-driven settings (see LockNotifyPolicy.qml).
    LockNotifyPolicy {
        id: lockNotifyPolicy
        trustedApps: LockConfig.notifTrustedApps
        privateApps: LockConfig.notifPrivateApps
        trustedCategories: LockConfig.notifTrustedCategories
        defaultMode: LockConfig.notifDefaultMode
    }

    // Live theme = the taskbar's source of truth (~/.config/theme/colors.json).
    // One global instance (colours are not per-output); passed to every surface so
    // lock colours track the bar instead of a frozen Gruvbox copy.
    Lib.ThemeEngine { id: lockTheme }

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

    // Per-output capture holders: `{ screenName: holderItem }`, consumed by the
    // pool delegates below.
    //
    // This map is DERIVED, never accumulated. Each live LockBackdrop holds one
    // claim (its holder + the output it currently believes it is on) and the
    // map is rebuilt from all claims on every change. That is load-bearing:
    // `WlSessionLockSurface.screen` oscillates while the surfaces are being
    // built -- observed HDMI-A-1 -> eDP-1 -> HDMI-A-1 on one surface -- so a
    // surface transiently claims its NEIGHBOUR's output. An accumulating map
    // keeps that bad entry forever and starves the rightful surface of its
    // capture (it renders the wallpaper while its neighbour shows the frozen
    // desktop). Rebuilding from claims makes every transient self-heal, because
    // the rightful owner's claim is still in the list when the blip resolves.
    property var holders: ({})
    property var claims: [] // [{ holder, name }] -- one entry per live backdrop

    // A backdrop (re)states which output it is on. An empty `name` retires the
    // claim, which is how a destroyed backdrop drops out on monitor unplug.
    function registerHolder(name, item) {
        if (!item)
            return;
        var next = [];
        var found = false;
        for (var i = 0; i < root.claims.length; i++) {
            var c = root.claims[i];
            if (c.holder === item) {
                found = true;
                next.push({ holder: item, name: name });
            } else {
                next.push(c);
            }
        }
        if (!found)
            next.push({ holder: item, name: name });
        root.claims = next;

        var map = {};
        for (var j = 0; j < next.length; j++) {
            if (next[j].name)
                map[next[j].name] = next[j].holder;
        }
        root.holders = map;
    }

    Instantiator {
        id: capturePool
        model: root.captureArmed ? Quickshell.screens : []
        // Re-check when the pool finishes building: a hasContent that arrives
        // while count < screens.length is rejected by _allCaptured() and would
        // otherwise never be re-polled.
        onObjectAdded: root._noteCapture()
        delegate: ScreencopyView {
            id: view
            required property var modelData
            // True only when the frame landed BEFORE the compositor lock
            // engaged. `hasContent` alone is not enough: it means "a frame
            // arrived", not "a useful frame arrived" -- a copy still in flight
            // when captureTimer locks will latch the post-lock (black) screen
            // and set hasContent true anyway.
            property bool preLockContent: false
            live: false
            captureSource: modelData

            // The view parents ITSELF into the holder registered for its own
            // output, and nothing else ever reparents it. `modelData` is stable
            // for the delegate's whole life, so this pairing cannot go wrong --
            // unlike a per-surface lookup, which resolves against a
            // briefly-unsettled `surface.screen` and lands on the neighbouring
            // output's view. Rendering the frozen frame must happen inside the
            // owning surface's scene graph; a GaussianBlur cannot source an
            // item from another window.
            readonly property Item targetHolder: (view.modelData && root.holders[view.modelData.name]) || null
            onTargetHolderChanged: view._reparent()
            Component.onCompleted: view._reparent()
            function _reparent() {
                if (view.targetHolder && view.parent !== view.targetHolder) {
                    view.parent = view.targetHolder;
                    view.anchors.fill = view.targetHolder;
                }
            }

            onHasContentChanged: {
                if (hasContent && !root.locked)
                    preLockContent = true;
                root._noteCapture();
            }
        }
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
    //
    // The budget MUST clear the slowest output's physical capture floor, or
    // that monitor silently loses the race every time and shows the wallpaper
    // while its neighbour shows the frozen desktop. wlr-screencopy delivers on
    // the output's next commit, so latency is quantised to its refresh
    // interval: ~6.9ms at 144Hz but ~16.7ms at 60Hz, and Instantiator builds
    // the delegates serially. Measured here: 17-30ms (144Hz) vs 24-41ms
    // (60Hz), with a miss past 50ms under load. 250ms is ~3 missed 60Hz frames
    // of headroom and is NOT the normal cost -- _noteCapture() stops the timer
    // the moment the last frame lands (~25-40ms), so only a genuinely failing
    // capture ever waits this long.
    Timer {
        id: captureTimer
        interval: 250
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
                theme: lockTheme
                backdropSource: root.wallpaperFor(surface.screen ? surface.screen.name : "")
                screenName: surface.screen ? surface.screen.name : ""
                registerHolder: root.registerHolder
                clockState: lockClockState
                weather: root.weather
                audio: root.audio
                notifications: root.notifications
                policy: lockNotifyPolicy
                notifHideAll: root.notifHideAll
                toggleNotifHideAll: function() { root.notifHideAll = !root.notifHideAll; }
                revealed: root.revealed
                onSurfaceReady: revealTimer.restart()
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
            root.notifHideAll = false;
        } else {
            root.revealed = false;
            root.captureArmed = false;  // destroys the views, frees the GPU buffers
            root.holders = ({});        // drop refs to the destroyed surfaces' holders
            root.claims = [];
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
