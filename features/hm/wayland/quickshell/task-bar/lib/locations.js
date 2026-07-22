.pragma library

// Weather locations, rendered as selectable chips. The "geo" entry resolves live
// via geoclue (lib/weather.sh `geo` mode); fixed entries carry explicit coords.
// Add more fixed cities here and they appear as chips automatically.
var list = [
    {
        id: "geo",
        label: "Current",
        geo: true
    },
    {
        id: "la",
        label: "LA",
        place: "Los Angeles, CA, USA",
        tz: "America/Los_Angeles",
        lat: "34.0522",
        lon: "-118.2437"
    },
    {
        id: "sf",
        label: "SF",
        place: "San Francisco, CA, USA",
        tz: "America/Los_Angeles",
        lat: "37.7749",
        lon: "-122.4194"
    },
    {
        id: "nyc",
        label: "NYC",
        place: "New York, NY, USA",
        tz: "America/New_York",
        lat: "40.7128",
        lon: "-74.0060"
    },
    {
        id: "durango",
        label: "DGO",
        place: "Durango, Durango, Mexico",
        tz: "America/Mexico_City",
        lat: "24.0277",
        lon: "-104.6532"
    }
];

function byId(id) {
    for (var i = 0; i < list.length; i++)
        if (list[i].id === id)
            return list[i];
    return list[0];
}

// weather.sh argv for a location entry, as an array so it can be exec'd
// directly (no shell). Passing the place name as its own token means an
// apostrophe city ("Coeur d'Alene") or a space survives without shell quoting,
// and the negative-lon coord is never re-split or treated as a flag. The chip
// shows the short `label`; the popup foot shows the full `place` (city, state,
// country), so the two are decoupled -- fall back to `label` if `place` is unset.
// The 5th token is the city IANA tz: weather.sh renders clock times in it (with
// the system-tz time in parens when they differ). "geo" (current location) omits
// it, so those times stay on the system clock with no parenthetical.
//   geo:   ["<id>", "geo"]   fixed: ["<id>", "<lat>", "<lon>", "<place>", "<tz>"]
function argsArrayFor(loc) {
    if (!loc)
        return ["geo"];
    if (loc.geo)
        return [loc.id, "geo"];
    return [loc.id, loc.lat, loc.lon, loc.place || loc.label, loc.tz || ""];
}
