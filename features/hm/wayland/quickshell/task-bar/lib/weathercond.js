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
