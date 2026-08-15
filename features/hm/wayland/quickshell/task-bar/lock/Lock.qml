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
    property var net: null // Lib.NetworkService, threaded from shell.qml
    property var router: null // Lib.RouterService, threaded from shell.qml
    property var bt: null // Lib.BluetoothService, threaded from shell.qml

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

    // Was a screen capture already running when the lock engaged?
    //
    // This MUST be sampled before the backdrop arms. The workspace backdrop uses
    // ScreencopyView, and Hyprland counts that as a screencast, so
    // `notifications.screencasting` is true for the WHOLE lock because of us --
    // sampling it any later would report a capture on every single lock. See
    // docs/lock-security-signals/spec.md.
    property bool castAtLock: false

    // True from the moment a lock engages until the first probe result for THAT
    // lock arrives. CommandPoll keeps its last value when `running` goes false
    // and back true, so without this the column would render the PREVIOUS
    // lock's readings -- including a stale "screen is being shared" -- for the
    // first seconds of every lock after the first.
    property bool secStale: true

    // A probe that fails or hangs never emits updated() (CommandPoll returns
    // early on a nonzero exit, watchdog kills included), so secStale would latch
    // true and SILENCE the "could not ask" warning during exactly the failure it
    // exists to report. Once this grace period passes with no fresh reading, the
    // state is genuinely unknown, not merely not-yet-known.
    property bool secGraceExpired: false

    // `lockContext.failCount` at the moment this lock engaged. LockContext.reset()
    // does NOT clear failCount, so the counter is cumulative for the process
    // lifetime; subtracting this baseline is what turns it into "attempts during
    // THIS lock".
    property int failBaseline: 0
    readonly property int failsThisLock: Math.max(0, lockContext.failCount - root.failBaseline)

    // A lock request always wins over an in-flight unlock detransition. Note
    // `root.locked = true` is a no-op when we are already locked (mid-
    // detransition), so onLockedChanged would not fire -- re-arm the reveal
    // and redo the lock-time resets here explicitly, or the surface stays
    // fully transparent AND keeps the just-authenticated password buffer.
    //
    // Wallpaper mode then locks immediately (unchanged MVP behaviour).
    // Workspace mode waits for the output set to settle, then arms the capture
    // pool and defers `locked` until every output's frame has landed (or
    // captureTimer's safety net fires).
    function lock() {
        unlockTimer.stop();
        if (root.locked) {
            lockContext.reset();
            root.refreshWallpapers();
            revealTimer.restart();
            return;
        }
        // Sample BEFORE anything below arms a capture -- see castAtLock.
        root.castAtLock = !!(root.notifications && root.notifications.screencasting);
        root.failBaseline = lockContext.failCount;
        root.secStale = true;
        root.secGraceExpired = false;
        if (LockConfig.secEnable)
            secFreshness.restart();
        if (!root.workspaceMode) {
            // Named explicitly: a wallpaper-mode lock and a workspace-mode lock
            // whose capture never ran look identical on screen.
            console.log(lockCapture, "wallpaper mode (backdropMode=" + LockConfig.backdropMode + "), no capture");
            root.locked = true;
            return;
        }
        root._armCaptureWhenSettled();
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
        lockSecurityState.lastUnlockMs = Date.now();           // "last unlock" readout
        unlockSessionProc.exec(["loginctl", "unlock-session"]); // fire unlock.target
        lockContext.reset();
        secFreshness.stop(); // must not fire against an unlocked session
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
    LockSecurityState { id: lockSecurityState }

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

    // Volatile security state, polled only while locked (idle on the desktop).
    // One script for all of it, so a tick costs one subprocess rather than three.
    Lib.CommandPoll {
        id: securityPoll
        interval: Math.max(1, LockConfig.secPollIntervalSec) * 1000
        running: root.locked && LockConfig.secEnable
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/lock-security-probe.sh"]
        parse: function (out) {
            try {
                var o = JSON.parse(String(out));
                return {
                    // `casts` stays null when the probe could not determine it.
                    // null and 0 are different answers and must not be merged:
                    // 0 means "nothing is capturing", null means "could not ask".
                    casts: (o.casts === null || o.casts === undefined) ? null : o.casts,
                    // Same three-state contract as `casts`, for the same
                    // reason: an undetectable camera and an idle camera are
                    // different answers. `|| 0` here would render "no camera
                    // in use" for a probe that could not look.
                    cams: (o.cams === null || o.cams === undefined) ? null : o.cams,
                    mics: (o.mics === null || o.mics === undefined) ? null : o.mics,
                    sessions: o.sessions || 0,
                    otherUsers: o.otherUsers || 0,
                    uptimeSec: o.uptimeSec || 0
                };
            } catch (e) {
                return null;
            }
        }
    }

    // Clears the staleness flag once a result for THIS lock lands, and restarts
    // the freshness watchdog below -- a fresh reading is exactly what proves the
    // probe is alive right now, not just at some point in the past. Safe against
    // CommandPoll's identical-output dedup (which skips `updated()` when stdout
    // repeats): the probe's JSON includes `uptimeSec`, which increments every
    // second while the poll interval is 10s, so two consecutive readings can
    // never be byte-identical and `updated()` is guaranteed to fire. Do not
    // "simplify" this away -- without that guarantee secStale could latch true
    // forever and the whole column would never appear.
    Connections {
        target: securityPoll
        function onUpdated() {
            // A parse failure (the JSON.parse catch path) leaves
            // securityPoll.value null. That is not a fresh reading -- it is
            // no reading at all -- so it must not clear secStale or restart
            // the watchdog: doing so would keep re-arming secFreshness on
            // every failed tick, and secGraceExpired could never become
            // true, silencing the "unknown" row during exactly the failure
            // it exists to report. Unreachable today (the probe script always
            // emits one atomic printf and exits 0), but the invariant is
            // worth keeping explicit rather than assumed.
            if (securityPoll.value === null)
                return;
            root.secStale = false;
            secFreshness.restart();
        }
    }

    // Watchdog on READING AGE, not lock age: restarted every time a fresh
    // reading lands (see onUpdated above) and on every fresh lock (see lock()),
    // so it measures "how long since we last heard anything" in BOTH the
    // cold-start case (probe has never answered this lock) and the mid-lock
    // case (probe answered once, then started failing/hanging on every later
    // tick). A probe that goes bad mid-lock never emits updated() again
    // (CommandPoll returns early on nonzero exit/watchdog kill), so without
    // this watchdog `_sec` would freeze on its last-good snapshot forever --
    // silently missing a capture that starts afterward, or leaving a stale
    // "Screen is being shared" alarm on screen after the capture stops.
    //
    // Deliberately has NO `running:` binding. Timer.restart() assigns
    // `running`, and an imperative assignment BREAKS a QML property binding --
    // a bound `running: root.locked && ...` would work until the first
    // restart() and then silently stop following `locked` back to false,
    // leaving this timer live after unlock. Driven explicitly instead: armed
    // in lock() and onUpdated above, disarmed in _release().
    //
    // UNTESTED by locksec-test.qml: this is pure Lock.qml wiring (Timer
    // restart/stop calls across lock()/onUpdated/_release()), not a formula in
    // LockSecurity.qml, and locksec-test.qml only ever instantiates
    // LockSecurity directly -- it has no Lock.qml/CommandPoll/Timer in scope to
    // drive. Verified instead by re-reading every `root.locked = true/false`
    // assignment in this file: `captureTimer`/`_noteCapture` only ever complete
    // an in-flight lock() call in workspace mode (lock() has already restarted
    // this timer before either can fire), so they need no restart/stop of
    // their own; the only path that sets `root.locked` without going through
    // lock()/_release() is the QS_LOCK_ESCAPE dev-only fail-open flash in
    // Component.onCompleted, which is out of this fix's scope (see task-5
    // fix-round-3 report).
    Timer {
        id: secFreshness
        interval: Math.max(3, Math.max(1, LockConfig.secPollIntervalSec) * 2) * 1000
        repeat: false
        onTriggered: {
            root.secStale = true;
            root.secGraceExpired = true;
        }
    }

    readonly property var _sec: securityPoll.value
    // Staleness is gated HERE, at the source, rather than in each consumer:
    // gating consumers one by one is what let the false alarm through last
    // round, and any future reader of secCasts would otherwise inherit the
    // same bug. While `secStale` is true, `_sec` may still hold the PREVIOUS
    // lock's result (CommandPoll does not clear `value` when `running` flips
    // false->true), so this reads as null -- "no answer yet" -- until a fresh
    // reading for THIS lock lands. `sharing` in LockSecurity.qml therefore
    // needs no staleness term of its own: a stale reading can never leak
    // through as a false "casts > 0".
    readonly property var secCasts: (root._sec && !root.secStale) ? root._sec.casts : null
    // Gated at the source for the same reason as secCasts -- a reading held
    // over from the PREVIOUS lock must not render as a live camera or mic.
    readonly property var secCams: (root._sec && !root.secStale) ? root._sec.cams : null
    readonly property var secMics: (root._sec && !root.secStale) ? root._sec.mics : null
    readonly property int secSessions: root._sec ? root._sec.sessions : 0
    readonly property int secOtherUsers: root._sec ? root._sec.otherUsers : 0
    readonly property int secUptimeSec: root._sec ? root._sec.uptimeSec : 0

    // True once the probe has returned at least one result FOR THIS LOCK.
    // Distinguishes "no reading yet" (the first moments of a lock) from "the
    // probe answered and could not determine", which look identical if you
    // only look at secCasts. The probe always exits 0, so CommandPoll primes
    // even on a null answer. `!root.secStale` is required in addition to the
    // null check because CommandPoll does NOT reset `value` to null when
    // `running` flips false->true, so `_sec` alone would stay non-null across
    // a re-lock and immediately render the PREVIOUS lock's (possibly stale)
    // reading -- see secStale above.
    readonly property bool secProbed: root._sec !== null && !root.secStale

    readonly property double lockSecurityLastUnlockMs: lockSecurityState.lastUnlockMs

    // Per-output desktop capture pool. MUST live here (a sibling of
    // WlSessionLock), not inside the lock surface: Hyprland stops compositing
    // the desktop the moment the lock request lands, which is before any
    // WlSessionLockSurface exists -- a capture started there would grab black.
    // `live: false` latches one frame, so it survives the desktop going dark.
    // Armed only for the duration of a lock; disarming destroys the views and
    // frees their GPU buffers. The frame never leaves the GPU swapchain.
    property bool captureArmed: false

    readonly property bool workspaceMode: LockConfig.backdropMode === "workspace"

    // ---- Capture diagnostics -------------------------------------------------
    //
    // The workspace backdrop has twice come up as the plain wallpaper with no
    // trace of why, and every input to that outcome is internal: captureArmed,
    // how long the settle gate waited, whether the pool built delegates, which
    // frames landed and whether they beat the lock. A healthy workspace-mode
    // lock reads arm -> pool built N of N -> settle armed -> frame
    // (preLock=true) -> "all captured", and any other shape names its own
    // failure.
    //
    // Gated at EMIT time: below Debug the category drops the message outright,
    // so it never reaches the .qslog either and there is no "off but still
    // recorded" fallback. Its own variable rather than HYPR_WL_DEBUG because
    // this costs six lines per lock and the protocol trace costs a line per
    // request; the debug session (features/nixos/desktop/wayland/
    // hyprland-wldebug.nix) sets both. For one run by hand, and it is read only
    // at startup so a reload will not do:
    //
    //   QS_LOCK_DEBUG=1 qs -c task-bar
    //   qs log -r 'lock.capture=true' \
    //     "$XDG_RUNTIME_DIR/quickshell/by-pid/$(pgrep -f 'quickshell -c task-bar')/log.qslog"
    LoggingCategory {
        id: lockCapture
        name: "lock.capture"
        defaultLogLevel: Quickshell.env("QS_LOCK_DEBUG") === "1" ? LoggingCategory.Debug : LoggingCategory.Warning
    }

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
        onObjectAdded: {
            console.log(lockCapture, "pool built " + capturePool.count + " of " + Quickshell.screens.length);
            root._noteCapture();
        }
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
                // preLock=false is the interesting failure: the capture worked
                // but lost the race, which looks identical on screen to a
                // capture that never ran.
                console.log(lockCapture, "frame " + (view.modelData ? view.modelData.name : "?")
                    + " hasContent=" + view.hasContent
                    + " preLock=" + view.preLockContent
                    + " locked=" + root.locked
                    + " parented=" + (view.parent !== null));
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
            console.log(lockCapture, "all captured, locking");
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
        onTriggered: {
            // Reaching here at all means at least one output's frame did not
            // land in time; the lock proceeds on the wallpaper fallback.
            console.log(lockCapture, "safety net fired after " + captureTimer.interval + "ms, locking without a full capture");
            root.locked = true;
        }
    }

    // ---- Output-settle gate (compositor-crash mitigation) --------------------
    //
    // Asking the compositor to capture an output it has ALREADY destroyed kills
    // it: Hyprland 0.56.0 derefs a null monitor in
    // CScreenshareFrame::transform() when an ext-image-copy-capture create_frame
    // lands after the output is gone, and the compositor dying takes the whole
    // session with it. Seen 2026-08-05: resume from S3 with the external monitor
    // unplugged while asleep -> we captured per `Quickshell.screens`, that list
    // still held HDMI-A-1, compositor SIGSEGV. See
    // docs/hyprland-screencopy-dead-output-crash. The real fix is the compositor
    // patch in overlays/; this gate is the client-side belt.
    //
    // Why a DELAY and not a check: a client cannot know an output is dead before
    // the compositor tells it. In the incident the removal had already happened
    // compositor-side but `global_remove` had not reached us yet, so every
    // reactive test ("did the screen list just change?", "is it still present?")
    // answers "all fine" and captures the corpse anyway. Waiting for the set to
    // hold still is the only thing that actually closes the window -- it lets
    // the queued removal land before we ask for anything.
    //
    // Cost, stated plainly: the compositor lock now engages ~settleMs later on
    // every workspace-mode lock, because the capture must precede the lock (the
    // desktop stops compositing the moment the lock request lands, so a
    // post-lock capture grabs black). That is a real, if small, window of
    // desktop visible after a lid-open. Set screenSettleMs to 0 to drop the
    // wait (capture then arms on the next event-loop turn, i.e. effectively the
    // old behaviour) once the patched compositor is deployed everywhere.
    readonly property int screenSettleMs: 250
    // Hard cap on deferral: a flapping output must never keep us out of the
    // lock. Past this, we give up on the capture, not on locking.
    readonly property int screenSettleCapMs: 1000
    property double _settleStartMs: 0

    function _armCaptureWhenSettled() {
        root._settleStartMs = Date.now();
        console.log(lockCapture, "arm requested, screens=" + Quickshell.screens.length);
        settleTimer.restart();
    }

    Connections {
        target: Quickshell
        // Topology moved while we were waiting -> restart the quiet period, up
        // to the cap. Past the cap we deliberately stop restarting so the
        // already-running timer fires and resolves (see onTriggered).
        function onScreensChanged() {
            if (!settleTimer.running)
                return;
            if (Date.now() - root._settleStartMs < root.screenSettleCapMs)
                settleTimer.restart();
        }
    }

    // The only `root.locked = true` site added by this gate; captureTimer /
    // _noteCapture remain the others (see the audit note above `secFreshness`).
    // Fail-open by construction: if this timer never fires nothing locks, which
    // matches qs-lock-trigger's own fail-open stance in swayidle.nix.
    Timer {
        id: settleTimer
        interval: root.screenSettleMs
        onTriggered: {
            if (root.locked)
                return;
            var waited = Date.now() - root._settleStartMs;
            if (waited >= root.screenSettleCapMs) {
                console.log(lockCapture, "settle hit the cap after " + waited + "ms, capture sacrificed");
                root.locked = true; // capture sacrificed, lock is not
                return;
            }
            root.captureArmed = true;
            console.log(lockCapture, "settle armed after " + waited + "ms, screens=" + Quickshell.screens.length);
            captureTimer.start();
        }
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
                net: root.net
                router: root.router
                bt: root.bt
                policy: lockNotifyPolicy
                notifHideAll: root.notifHideAll
                toggleNotifHideAll: function() { root.notifHideAll = !root.notifHideAll; }
                security: root
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
