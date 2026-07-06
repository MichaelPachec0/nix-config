// Pure helpers for the system stats popup. Plain top-level JS so it is both a
// QML JS resource (import "../lib/sysfmt.js" as SysFmt) and readable by the Deno
// test via indirect eval. Do NOT add `.pragma library`.

// Severity band for a metric value -> "good"|"fair"|"poor" (spec coloring table).
function severity(metric, value) {
    if (value === null || value === undefined || isNaN(value))
        return "good";
    var b = {
        cpu: [70, 88], mem: [70, 88], swap: [10, 50], temp: [70, 85], psi: [5, 20]
    }[metric];
    if (!b)
        return "good";
    if (value < b[0])
        return "good";
    if (value < b[1])
        return "fair";
    return "poor";
}

// Kilobytes (as reported by /proc/meminfo and ps rss) -> human string.
function fmtKB(kb) {
    var v = Number(kb) || 0;
    var u = ["K", "M", "G", "T"];
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
        v /= 1024;
        i++;
    }
    return (i >= 2 ? v.toFixed(1) : String(Math.round(v))) + u[i];
}

// Bytes/second -> human string (binary units).
function fmtRate(bps) {
    var v = Number(bps) || 0;
    var u = ["B", "K", "M", "G"];
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
        v /= 1024;
        i++;
    }
    return (i === 0 ? Math.round(v) : v.toFixed(1)) + " " + u[i] + "/s";
}
