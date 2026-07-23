pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "locations.js" as Locations
import "weathercond.js" as WeatherCond

// Background multi-city weather watcher. Tier-polls every city (the current
// physical location -- geo -- fast, the others slow), diffs each city's active
// condition keys against the last scan, and notify-sends started/cleared
// transitions. One instance, hoisted to ShellRoot (Task 10), decoupled from the
// per-monitor weatherState selection (minutely nowcast precision matters most
// for where the user physically is, not whichever remote city a given monitor
// happens to have selected). Persists a per-city key set so a restart does not
// re-notify conditions that were already active.
//
// One CommandPoll per city (an Instantiator over Locations.list) reuses the
// repo's Process+StdioCollector poll idiom: it collects stdout, keeps the
// last-good reading on a nonzero exit, dedups identical output (so _apply only
// runs on CHANGED weather), and watchdogs a hung child. The correctness-critical
// diff is the pure WeatherCond.diffConditions (deno-tested in weathercond.test.js).
//
// Persistence: this uses a single `property string stateJson` (JSON.parse /
// JSON.stringify by hand), NOT a nested `property var state`. The persisted
// shape is a plain object-of-objects ({ cityId: { key: {kind,sev,label} } });
// there is no in-repo precedent for JsonAdapter round-tripping a nested `var`
// (CalState/InhibitService/SysPopup all persist flat scalars), so serializing to
// a string ourselves is deterministic and sidesteps any QJSValue nested-var
// serialization ambiguity. Single-writer, watchChanges:false + explicit
// writeAdapter() -- same discipline as InhibitService.
Scope {
    id: watch

    readonly property string _home: Quickshell.env("HOME")
    readonly property string _script: watch._home + "/.config/quickshell/task-bar/lib/weather.sh"
    readonly property string _stateDir: (Quickshell.env("XDG_STATE_HOME") || (watch._home + "/.local/state")) + "/quickshell"

    // Gates the pollers so the very first poll's _apply never races the async
    // FileView.reload() (Component.onCompleted below): without this, a poll
    // that lands before the state file has loaded reads stateJson as still
    // "{}" and re-notifies every already-active condition on every restart,
    // defeating the whole point of persisting state. Set true by whichever of
    // FileView's onLoaded/onLoadFailed fires first (both are real signals --
    // see InhibitService.qml's onLoaded and Quickshell's FileView), with a 1s
    // Timer fallback so a missing/unreadable state file (a signal that never
    // fires would otherwise be possible in principle) can NEVER hang polling
    // forever -- worst case is a one-time boot burst of re-notifications,
    // which is an acceptable, expected first-run tradeoff.
    property bool _ready: false

    // Parse the persisted {cityId -> {key -> cond}} map, defaulting to {}.
    function _readState() {
        try {
            var o = JSON.parse(adapter.stateJson || "{}");
            return (o && typeof o === "object") ? o : {};
        } catch (e) {
            return {};
        }
    }
    function _writeState(obj) {
        adapter.stateJson = JSON.stringify(obj || {});
        file.writeAdapter(); // persist once, explicitly (watchChanges is off)
    }

    // Fire notify-send for one transition. phase: "start" | "clear". A clear is
    // always low urgency + a shorter timeout; a start inherits the condition's
    // urgency (critical -> persistent, timeout 0) from the pure helper.
    function _notify(city, cond, phase) {
        var urg = phase === "clear" ? "low" : WeatherCond.urgency(cond.kind, cond.sev);
        var title = "Weather - " + city.label;
        var body = phase === "clear" ? (WeatherCond.notifBody(cond) + " cleared") : WeatherCond.notifBody(cond);
        var timeout = urg === "critical" ? "0" : (phase === "clear" ? "8000" : "10000");
        Quickshell.execDetached(["notify-send", "-a", "Weather", "-u", urg, "-t", timeout, title, body]);
    }

    // Compare a city's fresh conditions to its persisted key set, emit the
    // started/cleared transitions, and persist the fresh set for the next scan.
    function _apply(city, conditions) {
        var state = watch._readState();
        var prev = state[city.id] || {};
        var d = WeatherCond.diffConditions(prev, conditions || []);
        for (var i = 0; i < d.started.length; i++)
            watch._notify(city, d.started[i], "start");
        for (var j = 0; j < d.cleared.length; j++)
            watch._notify(city, d.cleared[j], "clear");
        state[city.id] = d.next;
        watch._writeState(state);
    }

    // One tier-polling scanner per city. CommandPoll is a sibling in lib/, so it
    // resolves by name with no import. isCurrent picks the fast cadence + a short
    // cache TTL for the geo (current physical location) entry and the slow
    // cadence for the rest -- independent of any per-monitor weatherState
    // selection.
    Instantiator {
        model: Locations.list
        delegate: CommandPoll {
            id: poll
            required property var modelData
            readonly property bool isCurrent: modelData.id === "geo"
            // Held off until the persisted state has loaded (or the fallback
            // Timer below fires), so the first tick's _apply never runs
            // against a not-yet-populated adapter.stateJson.
            running: watch._ready
            interval: isCurrent ? 300000 : 1800000
            command: ["env", "WEATHER_TTL=" + (isCurrent ? "300" : "1800"), watch._script].concat(Locations.argsArrayFor(modelData))
            parse: function (out) {
                try {
                    return JSON.parse(String(out));
                } catch (e) {
                    return null;
                }
            }
            onUpdated: if (poll.value)
                watch._apply(poll.modelData, poll.value.conditions || [])
        }
    }

    // FileView does not create parent dirs; guarantee the state dir first.
    Process {
        running: true
        command: ["mkdir", "-p", watch._stateDir]
    }
    FileView {
        id: file
        path: watch._stateDir + "/weather-watch-state.json"
        watchChanges: false
        onLoaded: watch._ready = true
        onLoadFailed: watch._ready = true // e.g. first run, no state file yet
        Component.onCompleted: reload()

        JsonAdapter {
            id: adapter
            property string stateJson: "{}"
        }
    }

    // Safety net: reload() is async and, in principle, could be delayed or
    // (if some future edit changes how the file is loaded) never signal at
    // all. Polling must never hang on that, so force readiness after ~1s
    // regardless of whether FileView has reported in yet.
    Timer {
        interval: 1000
        running: true
        repeat: false
        onTriggered: watch._ready = true
    }
}
