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
        label: "Los Angeles",
        lat: "34.0522",
        lon: "-118.2437"
    }
];

function byId(id) {
    for (var i = 0; i < list.length; i++)
        if (list[i].id === id)
            return list[i];
    return list[0];
}

// weather.sh argv for a location entry, as an array so it can be exec'd
// directly (no shell). Passing the label as its own token means an apostrophe
// city ("Coeur d'Alene") or a space survives without shell quoting, and the
// negative-lon coord is never re-split or treated as a flag.
//   geo:   ["<id>", "geo"]      fixed: ["<id>", "<lat>", "<lon>", "<label>"]
function argsArrayFor(loc) {
    if (!loc)
        return ["geo"];
    if (loc.geo)
        return [loc.id, "geo"];
    return [loc.id, loc.lat, loc.lon, loc.label];
}
