// Pure formatters shared by the router surfaces. Plain top-level JS so it is
// both a QML JS resource (import "../lib/routerfmt.js" as RouterFmt) and
// readable by the Deno test via indirect eval. Do NOT add `.pragma library`.

// Signal-quality band -> "good"|"fair"|"poor" (spec section 9).
function quality(metric, value) {
    if (value === null || value === undefined || isNaN(value))
        return "poor";
    var b = { rsrp: [-90, -105], rsrq: [-11, -16], sinr: [13, 0] }[metric];
    if (!b)
        return "poor";
    if (value >= b[0])
        return "good";
    if (value >= b[1])
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
