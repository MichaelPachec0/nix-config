// features/hm/wayland/quickshell/task-bar/lib/notifstack.js
// Collapses notifications with IDENTICAL content into stacks, so a chatty
// source renders as one card with an "xN" count instead of N identical cards.
// Pure and stateless (.pragma library) so it is unit-testable headless and
// shared by the lock, hub and toast surfaces.
.pragma library

// Unit separator (U+001F). Fields are length-prefixed because their bytes are
// app-controlled (from the D-Bus Notify call), so a separator byte can appear in
// them. Prefixing prevents a separator within a field value from forging a
// boundary: the length pins where each field ends. Written as an ESCAPE, never
// a literal control byte: a raw 0x1f in source survives neither copy-paste nor
// the repo's ASCII-only rule.
var SEP = "\x1f";

function _s(v) {
    return (v === undefined || v === null) ? "" : String(v);
}

// Length-prefix each field so a separator byte embedded in a field value
// cannot forge a boundary: the length pins where each field ends, so
// ("a", "b<SEP>c") and ("a<SEP>b", "c") can no longer produce the same key.
// These fields come from the D-Bus Notify call and are entirely
// app-controlled, so this cannot be assumed away.
function _field(v) {
    var s = _s(v);
    return s.length + ":" + s;
}

// The identity of "this same notification again".
//
// `desktopEntry` and `urgency` are part of the key for a SECURITY reason, not a
// cosmetic one: the lock derives its privacy tier from appName/desktopEntry/
// category/urgency, so two notifications with identical visible text but a
// different desktopEntry or urgency can classify into DIFFERENT tiers. Merging
// those and rendering at one member's tier could expose a private
// notification's content. Keying on them keeps every stack tier-homogeneous.
function stackKey(n) {
    return [_field(n.appName), _field(n.desktopEntry), _field(n.summary), _field(n.body), _field(n.urgency)].join(SEP);
}

// Group `list` into stacks. `seenAt` is NotifService's id -> epoch ms map.
//
// Stack order follows FIRST APPEARANCE in `list`, and callers pass a
// newest-first list (NotifService keeps `items`/`toasts` newest-first), so a
// repeat re-floats its stack to the top for free. Deliberately no sort by
// `newest`: an unstamped stack has newest 0 and would sort to the bottom,
// which would reorder the list for a reason the user cannot see.
function stacksOf(list, seenAt) {
    var map = {};
    var order = [];
    for (var i = 0; i < list.length; i++) {
        var n = list[i];
        var k = stackKey(n);
        if (!map[k]) {
            map[k] = { key: k, list: [], count: 0, newest: 0, oldest: 0 };
            order.push(k);
        }
        var st = map[k];
        st.list.push(n);
        st.count = st.list.length;
        var t = (seenAt && seenAt[n.id] > 0) ? seenAt[n.id] : 0;
        if (t > 0) {
            if (st.newest === 0 || t > st.newest)
                st.newest = t;
            if (st.oldest === 0 || t < st.oldest)
                st.oldest = t;
        }
    }
    return order.map(function (k) {
        return map[k];
    });
}
