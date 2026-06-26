.pragma library

// Canonical condition key -> MDI weather glyph (Nerd Font code point). Shared by
// the hub Calendar/Weather card and the bar weather widget so the table lives in
// one place. Keys are produced by lib/weather.sh (which normalizes every
// provider's vocabulary onto this set).
var glyphs = {
    "clear-day": 0xF0599,           // weather-sunny
    "clear-night": 0xF0594,         // weather-night
    "partly-cloudy-day": 0xF0595,   // weather-partly-cloudy
    "partly-cloudy-night": 0xF0F31, // weather-night-partly-cloudy
    "cloudy": 0xF0590,              // weather-cloudy
    "fog": 0xF0591,                 // weather-fog
    "drizzle": 0xF0F33,             // weather-partly-rainy
    "rain": 0xF0597,                // weather-rainy
    "showers": 0xF0596,             // weather-pouring
    "sleet": 0xF067F,               // weather-snowy-rainy
    "snow": 0xF0598,                // weather-snowy
    "thunder": 0xF067E,             // weather-lightning-rainy
    "tornado": 0xF0F3A              // weather-tornado
};

function glyph(key) {
    var cp = glyphs[key];
    return String.fromCodePoint(cp ? cp : 0xF0590);
}

// Readable condition word from a canonical key (used by forecast rows).
function descFromKey(key) {
    switch (key) {
    case "clear-day":
    case "clear-night":
        return "Clear";
    case "partly-cloudy-day":
    case "partly-cloudy-night":
        return "Partly cloudy";
    case "cloudy":
        return "Cloudy";
    case "fog":
        return "Fog";
    case "drizzle":
        return "Drizzle";
    case "rain":
        return "Rain";
    case "showers":
        return "Showers";
    case "sleet":
        return "Sleet";
    case "snow":
        return "Snow";
    case "thunder":
        return "Thunderstorm";
    case "tornado":
        return "Tornado";
    default:
        return "";
    }
}

// Human-readable provider name for the "via ..." provenance line.
function sourceLabel(s) {
    switch (s) {
    case "owm":
        return "OpenWeatherMap";
    case "pirate":
        return "PirateWeather";
    case "metno":
        return "met.no";
    case "openmeteo":
        return "Open-Meteo";
    case "wttr":
        return "wttr.in";
    default:
        return "";
    }
}
