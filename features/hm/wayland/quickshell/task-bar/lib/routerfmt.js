// Pure formatters shared by the router surfaces. Plain top-level JS so it is
// both a QML JS resource (import "../lib/routerfmt.js" as RouterFmt) and
// readable by the Deno test via indirect eval. Do NOT add `.pragma library`.

// Signal-quality band thresholds per metric ([excellent, good, fair] cutoffs),
// descending. Module-level so the table is built once, not rebuilt on every
// quality() call.
var QUALITY_BANDS = { rsrp: [-100, -105, -110], rsrq: [-12, -16, -20], sinr: [12, 6, 0] };

// Signal-quality band -> "excellent"|"good"|"fair"|"poor" (spec section 9).
function quality(metric, value) {
    if (value === null || value === undefined || isNaN(value))
        return "poor";
    var b = QUALITY_BANDS[metric];
    if (!b)
        return "poor";
    if (value >= b[0])
        return "excellent";
    if (value >= b[1])
        return "good";
    if (value >= b[2])
        return "fair";
    return "poor";
}

// Modem strength (0..5) -> clamped integer bar fill count.
function barFill(strength) {
    var n = Math.round(Number(strength));
    if (isNaN(n) || n < 0)
        return 0;
    return n > 5 ? 5 : n;
}

// Bytes/sec -> human bits/sec string.
function fmtRate(bytesPerSec) {
    var bits = (Number(bytesPerSec) || 0) * 8;
    var u = ["b/s", "Kb/s", "Mb/s", "Gb/s"];
    var i = 0;
    while (bits >= 1000 && i < u.length - 1) {
        bits /= 1000;
        i++;
    }
    return (i === 0 ? String(Math.round(bits)) : bits.toFixed(1)) + " " + u[i];
}

// Seconds -> compact duration ("3d 4h", "3h 31m", "45m", "12s").
//
// Two units at most, largest first, and the smaller one dropped when it is
// zero. The router's own uptime runs to days while the modem's is often
// minutes, and both share this line -- a bare hour count rounded 3h31m to "3h"
// and made a link that had just redialled look stable.
//
// Returns "--" for null/undefined/negative rather than "0s", so an unpopulated
// reading never reads as a freshly booted device.
function fmtDuration(seconds) {
    var s = Number(seconds);
    if (seconds === null || seconds === undefined || isNaN(s) || s < 0)
        return "--";
    s = Math.floor(s);
    var d = Math.floor(s / 86400);
    var h = Math.floor((s % 86400) / 3600);
    var m = Math.floor((s % 3600) / 60);
    if (d > 0)
        return h > 0 ? (d + "d " + h + "h") : (d + "d");
    if (h > 0)
        return m > 0 ? (h + "h " + m + "m") : (h + "h");
    if (m > 0)
        return m + "m";
    return s + "s";
}

// Bytes -> human string (binary units).
function fmtBytes(n) {
    var b = Number(n) || 0;
    var u = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    while (b >= 1024 && i < u.length - 1) {
        b /= 1024;
        i++;
    }
    return (i === 0 ? String(Math.round(b)) : b.toFixed(1)) + " " + u[i];
}
