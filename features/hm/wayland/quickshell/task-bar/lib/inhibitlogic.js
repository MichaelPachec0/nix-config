// Pure inhibit logic shared by the bar widgets, the service, and the popup.
// Plain top-level JS so it is both a QML JS resource
// (import "inhibitlogic.js" as InhibitLogic) and readable by the Deno test via
// indirect eval. Do NOT add `.pragma library`. ASCII-only: the infinity glyph
// is produced by code point, never embedded as a literal character.

// Milliseconds remaining -> "HH:MM:SS" (zero-padded; clamps negatives to 0).
function formatCountdown(remainingMs) {
    var s = Math.max(0, Math.floor((Number(remainingMs) || 0) / 1000));
    var hh = Math.floor(s / 3600);
    var mm = Math.floor((s % 3600) / 60);
    var ss = s % 60;
    function p(n) { return (n < 10 ? "0" : "") + n; }
    return p(hh) + ":" + p(mm) + ":" + p(ss);
}

// The infinity mark (U+221E), assembled from its code point to keep source ASCII.
function infinityGlyph() { return String.fromCodePoint(0x221E); }

// Canonical empty state (nested shape used by all logic here).
function defaultState() {
    return {
        idle: { on: false, expiry: 0 },
        sleep: { on: false, expiry: 0 },
        locked: false,
        lastDurationMs: 3600000,
        idleDefaultMs: 0,
        sleepDefaultMs: 0,
    };
}

function _concern(raw) {
    var c = (raw && typeof raw === "object") ? raw : {};
    return { on: c.on === true, expiry: Number(c.expiry) || 0 };
}

// Coerce anything (missing keys, wrong types, corrupt JSON result) into a valid
// nested state, filling from defaults.
function sanitizeState(raw) {
    var r = (raw && typeof raw === "object") ? raw : {};
    var d = defaultState();
    function dur(v, dflt) {
        return (v === 0 || Number(v) > 0) ? Number(v) : dflt;
    }
    return {
        idle: _concern(r.idle),
        sleep: _concern(r.sleep),
        locked: r.locked === true,
        lastDurationMs: dur(r.lastDurationMs, d.lastDurationMs),
        idleDefaultMs: dur(r.idleDefaultMs, d.idleDefaultMs),
        sleepDefaultMs: dur(r.sleepDefaultMs, d.sleepDefaultMs),
    };
}

// Turn off any timed concern whose expiry has already passed (elapsed while the
// shell was not running). Indefinite (expiry 0) never expires. Mutates + returns.
function reconcileOnLoad(state, nowMs) {
    ["idle", "sleep"].forEach(function (k) {
        var c = state[k];
        if (c.on && c.expiry > 0 && c.expiry <= nowMs) {
            c.on = false;
            c.expiry = 0;
        }
    });
    return state;
}

// The single on/expiry both concerns share when locked: off if neither is on;
// otherwise a running timer wins -- the latest timed expiry is replicated onto
// both, even over an off or on-indefinite concern (so locking propagates a set
// timer to the "non-initialized" side). Both go indefinite (expiry 0) only when
// no on-concern is timed.
function coupledState(state) {
    var idle = state.idle, sleep = state.sleep;
    if (!idle.on && !sleep.on) return { on: false, expiry: 0 };
    var e = 0;
    if (idle.on && idle.expiry > 0) e = Math.max(e, idle.expiry);
    if (sleep.on && sleep.expiry > 0) e = Math.max(e, sleep.expiry);
    return { on: true, expiry: e };
}

// Enable lock: both concerns adopt the coupled state.
function applyLock(state) {
    var c = coupledState(state);
    state.idle = { on: c.on, expiry: c.expiry };
    state.sleep = { on: c.on, expiry: c.expiry };
    state.locked = true;
    return state;
}

// Disable lock: concerns split (already equal; free to diverge afterwards).
function applyUnlock(state) {
    state.locked = false;
    return state;
}
