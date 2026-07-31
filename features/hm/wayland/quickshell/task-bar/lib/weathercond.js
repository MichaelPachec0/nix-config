// Pure helpers mapping a weather condition's kind/sev to a theme color, a
// notification urgency, notification text, and a severity sort. Plain
// top-level JS so it is both a QML JS resource (import "../lib/weathercond.js"
// as WeatherCond) and readable by the Deno test via indirect eval. Do NOT add
// `.pragma library`.

// kind -> theme color-token NAME (resolved against the theme object by color()).
// sev only escalates heat (warn=orange, severe=red) and uv (both purple).
var TOKEN = {
    heat: "accentRed", cold: "accentBlue", rain: null, snow: null,
    wind: "accentYellow", uv: "accentPurple", fog: "textSecondary",
    thunder: "accentRed", hydroplaning: "accentOrange", nws: "accentRed"
};
function color(theme, kind, sev) {
    if (kind === "rain") return "#4d8fd6";
    if (kind === "snow") return "#a9d5e5";
    if (kind === "heat") return sev === "severe" ? theme.accentRed : theme.accentOrange;
    var t = TOKEN[kind];
    return t ? theme[t] : theme.accentRed;
}
function urgency(kind, sev) {
    if (kind === "nws" || kind === "thunder") return "critical";
    if (sev === "severe") return "critical";
    return "normal";
}
var RANK = { severe: 0, warn: 1, info: 2 };
function sortBySeverity(list) {
    return (list || []).slice().sort(function (a, b) {
        return (RANK[a.sev] ?? 3) - (RANK[b.sev] ?? 3);
    });
}
function notifBody(cond) {
    return cond && cond.label ? cond.label : "Weather condition";
}

// Stable event key for a condition: nws alerts are keyed by their (unique)
// title so two concurrent alerts are tracked separately; everything else is
// keyed by kind (one active heat/rain/... per city at a time). WeatherWatch
// persists a {key -> cond} map per city and diffs against it.
// Guarded: a malformed/falsy cond (e.g. a bad weather.sh payload) has no kind
// to key on, so it maps to "" rather than throwing inside _apply.
function keyOf(cond) {
    if (!cond || !cond.kind)
        return "";
    return cond.kind === "nws" ? ("nws:" + cond.label) : cond.kind;
}

// Diff a city's freshly-scanned conditions against its previously-persisted
// {key -> cond} map. Returns:
//   started: fresh conds whose key was NOT persisted (new -> notify start)
//   cleared: persisted conds whose key is NOT in the fresh set (gone -> notify clear)
//   next:    the fresh key -> cond map (what to persist for the next scan; the
//            whole cond is stored so a later "cleared" still has its label)
// A key present in both is unchanged (no notification), and next carries the
// fresh cond so an updated label is kept.
function diffConditions(prevLabels, freshConditions) {
    var prev = prevLabels || {};
    var fresh = freshConditions || [];
    var next = {};
    var started = [];
    for (var i = 0; i < fresh.length; i++) {
        var c = fresh[i];
        var k = keyOf(c);
        if (!k)
            continue; // malformed/keyless entry -> skip, no phantom event
        next[k] = c;
        if (!prev[k])
            started.push(c);
    }
    var cleared = [];
    for (var pk in prev) {
        if (Object.prototype.hasOwnProperty.call(prev, pk) && !next[pk])
            cleared.push(prev[pk]);
    }
    return {
        started: started,
        cleared: cleared,
        next: next
    };
}

// "6:00 PM (in 2h)" for a condition's end time -- the forward-looking twin of
// notiftime.js's fmtStamp, which clamps the past-facing case to "just now" and
// so cannot express a deadline. Only NWS alerts carry one; every other kind is
// derived from the current snapshot and ends whenever the next poll says so.
//
// Returns "" for a missing, zero, or already-past deadline. An expired alert
// should disappear from the list rather than render "in 0m", and a provider
// that omits the field must not print an epoch-zero date.
function fmtUntil(nowMs, thenMs, use12h) {
    if (!(thenMs > 0) || thenMs <= nowMs)
        return "";
    var then = new Date(thenMs);
    var h = then.getHours();
    var m = then.getMinutes();
    var clock;
    if (use12h) {
        var h12 = h % 12;
        if (h12 === 0)
            h12 = 12;
        clock = h12 + ":" + (m < 10 ? "0" : "") + m + (h < 12 ? " AM" : " PM");
    } else {
        clock = (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }
    // Name the day when the deadline is not today, so "6:00 PM" cannot be read
    // as tonight when it is tomorrow evening.
    var now = new Date(nowMs);
    if (now.getFullYear() !== then.getFullYear() || now.getMonth() !== then.getMonth() || now.getDate() !== then.getDate())
        clock = _DAYS_UNTIL[then.getDay()] + " " + clock;

    var mins = Math.floor((thenMs - nowMs) / 60000);
    var rel;
    if (mins < 1)
        rel = "in under a minute";
    else if (mins < 60)
        rel = "in " + mins + "m";
    else if (mins < 60 * 24)
        rel = "in " + Math.floor(mins / 60) + "h";
    else
        rel = "in " + Math.floor(mins / (60 * 24)) + "d";
    return clock + " (" + rel + ")";
}
var _DAYS_UNTIL = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
