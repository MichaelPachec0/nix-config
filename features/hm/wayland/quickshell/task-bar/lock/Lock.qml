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

    function lock() { root.locked = true; }

    // Unlock is a two-phase move: play the detransition, then release. The
    // Timer -- not any animation signal -- is the authority, so a skipped or
    // broken animation can never strand the session locked.
    function unlock() { root.beginUnlock(); }

    function beginUnlock() {
        if (!root.locked)
            return;
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
