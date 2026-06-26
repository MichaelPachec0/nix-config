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

// weather.sh argument string for a location entry.
//   geo:   "<id> geo"            fixed: "<id> <lat> <lon> '<label>'"
function argsFor(loc) {
    if (!loc)
        return "geo";
    if (loc.geo)
        return loc.id + " geo";
    return loc.id + " " + loc.lat + " " + loc.lon + " '" + loc.label + "'";
}
