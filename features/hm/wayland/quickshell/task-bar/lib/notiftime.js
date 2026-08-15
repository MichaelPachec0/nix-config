// features/hm/wayland/quickshell/task-bar/lib/notiftime.js
// Formats a notification's arrival time as "14:32 (2m ago)" -- clock first,
// relative age in parentheses. Pure and stateless (.pragma library) so it is
// unit-testable headless and shared by the lock, hub and toast surfaces.
//
// A stamp of 0 (or missing) means "no recorded arrival time" -- e.g. a
// notification that predates NotifService.seenAt -- and formats to the empty
// string. Callers render nothing rather than a wrong time.
.pragma library

var _DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function _pad2(n) {
    return n < 10 ? "0" + n : String(n);
}

function _clock(then, use12h) {
    var h = then.getHours();
    var m = _pad2(then.getMinutes());
    if (!use12h)
        return _pad2(h) + ":" + m;
    var ap = h < 12 ? "AM" : "PM";
    var h12 = h % 12;
    if (h12 === 0)
        h12 = 12;
    return h12 + ":" + m + " " + ap;
}

function _sameDay(a, b) {
    return a.getFullYear() === b.getFullYear()
        && a.getMonth() === b.getMonth()
        && a.getDate() === b.getDate();
}

// Coarse age wording; minute granularity is all the display needs. A future
// stamp (clock skew) clamps to 0 rather than printing a negative age.
function _relative(nowMs, thenMs) {
    var s = Math.floor((nowMs - thenMs) / 1000);
    if (s < 0)
        s = 0;
    if (s < 60)
        return "just now";
    var m = Math.floor(s / 60);
    if (m < 60)
        return m + "m ago";
    var h = Math.floor(m / 60);
    if (h < 24)
        return h + "h ago";
    return Math.floor(h / 24) + "d ago";
}

function fmtStamp(nowMs, thenMs, use12h) {
    if (!(thenMs > 0))
        return "";
    var now = new Date(nowMs);
    var then = new Date(thenMs);
    var clock = _clock(then, use12h);
    if (!_sameDay(now, then))
        clock = _DAYS[then.getDay()] + " " + clock;
    return clock + " (" + _relative(nowMs, thenMs) + ")";
}
