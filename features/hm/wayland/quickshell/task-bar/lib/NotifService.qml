import QtQuick
import Quickshell.Services.Notifications
import "notifstack.js" as NotifStack

// Global notification service: owns the Quickshell NotificationServer (acquires
// org.freedesktop.Notifications, replacing swaync) and maintains two reactive
// lists -- `items` (persistent, for the hub card) and `toasts` (transient, for
// the popup overlay). Both hold the same Notification objects with different
// lifetimes. DND (and an active screencast) suppress new toasts; notifications
// still land in `items`. Instantiated once at the ShellRoot level.
//
// We keep our own arrays rather than binding to server.trackedNotifications
// because that model's value-changes don't drive QML bindings reactively; here
// reassigning the arrays does. Each notification is removed on its `closed`
// signal (dismissed, expired, or replaced).
QtObject {
    id: svc

    property bool dnd: false
    // Suppresses new toasts without touching the user's manual `dnd`. Driven by
    // shell.qml off Hyprland's `screencast` IPC event -- the QS-native stand-in
    // for swaync's screencast inhibitor (notifications still land in `items`).
    property bool screencasting: false
    property var items: []  // persistent (newest first)
    property var toasts: [] // transient popups (newest first)

    readonly property int count: svc.items.length

    // Per-app grouping (derived). Newest group first, newest card first.
    readonly property var groups: svc.groupBy(svc.items)
    readonly property var toastGroups: svc.groupBy(svc.toasts)

    // Expand/collapse state per app, kept here so it survives model rebuilds.
    property var expandedApps: ({})

    // Arrival time per notification id, in epoch ms.
    //
    // The Quickshell Notification type carries NO timestamp, so this map is the
    // only record of when something fired. It MUST be stamped here in
    // onNotification: this service is the only always-live observer, whereas a
    // renderer (the lock surface especially) is constructed later and would
    // stamp its own construction time for every notification already waiting.
    property var seenAt: ({})

    function timeOf(n) {
        return (n && svc.seenAt[n.id] > 0) ? svc.seenAt[n.id] : 0;
    }

    function _stamp(n) {
        var m = {};
        for (var k in svc.seenAt)
            m[k] = svc.seenAt[k];
        m[n.id] = Date.now();
        svc.seenAt = m;
    }

    // Keep `seenAt` to the ids still present in items or toasts. Called from
    // both addItem (which silently drops past its 100 cap) and removeItem, so
    // the map cannot outgrow the lists -- same reason _pruneToastExpiry exists.
    function _pruneSeenAt() {
        var live = {};
        var i;
        for (i = 0; i < svc.items.length; i++)
            live[svc.items[i].id] = true;
        for (i = 0; i < svc.toasts.length; i++)
            live[svc.toasts[i].id] = true;
        var m = {};
        for (var k in svc.seenAt)
            if (live[k])
                m[k] = svc.seenAt[k];
        svc.seenAt = m;
    }

    // Toast auto-dismiss for stacks: "perCard" (each card expires on its own) or
    // "stack" (a whole app group expires together). Tunable.
    property string toastTimerMode: "perCard"
    property real toastTimeoutMs: 5000
    property bool toastPaused: false  // true while the toast overlay is hovered
    property var toastExpiry: ({})    // notification id -> epoch ms (absent = sticky)

    function setExpiry(n, when) {
        var e = {};
        for (var k in svc.toastExpiry)
            e[k] = svc.toastExpiry[k];
        e[n.id] = when;
        svc.toastExpiry = e;
    }
    // Restart the countdown for every live toast (called when hover ends).
    function refreshToastTimers() {
        var now = Date.now();
        var e = {};
        for (var i = 0; i < svc.toasts.length; i++) {
            var n = svc.toasts[i];
            if (n.urgency !== NotificationUrgency.Critical)
                e[n.id] = now + svc.toastTimeoutMs;
        }
        svc.toastExpiry = e;
    }

    property Timer toastSweep: Timer {
        interval: 400
        repeat: true
        running: svc.toasts.length > 0 && !svc.toastPaused
        onTriggered: {
            var now = Date.now();
            if (svc.toastTimerMode === "stack") {
                var gs = svc.toastGroups;
                for (var g = 0; g < gs.length; g++) {
                    var x = svc.toastExpiry[gs[g].list[0].id]; // newest card's timer
                    if (x !== undefined && now >= x)
                        svc.removeToastApp(gs[g].app);
                }
            } else {
                var expired = svc.toasts.filter(function (n) {
                    var e = svc.toastExpiry[n.id];
                    return e !== undefined && now >= e;
                });
                for (var i = 0; i < expired.length; i++)
                    svc.removeToast(expired[i]);
            }
        }
    }

    function keyOf(n) {
        return (n.appName && String(n.appName).length) ? String(n.appName) : "Notifications";
    }
    function groupBy(arr) {
        var map = {};
        var order = [];
        for (var i = 0; i < arr.length; i++) {
            var k = svc.keyOf(arr[i]);
            if (!map[k]) {
                map[k] = [];
                order.push(k);
            }
            map[k].push(arr[i]);
        }
        return order.map(function (k) {
            return {
                app: k,
                list: map[k]
            };
        });
    }

    // Identical-content stacking (see lib/notifstack.js). Kept as a wrapper so
    // callers do not have to know about `seenAt`.
    function stackKey(n) {
        return NotifStack.stackKey(n);
    }
    function stacksOf(list) {
        return NotifStack.stacksOf(list, svc.seenAt);
    }
    // A stack is ONE visual unit, so dismissing it must close every member --
    // otherwise the hidden duplicates would resurface as a fresh stack.
    function dismissStack(stack) {
        var snap = stack.list.slice();
        for (var i = 0; i < snap.length; i++)
            snap[i].dismiss();
    }

    // Shared clock for relative timestamps ("2m ago"). ONE 30s tick for every
    // surface instead of a timer per card; minute granularity is all the
    // wording needs. Idle while nothing is showing. Renderers must read this
    // property inside their text binding, or the age never repaints.
    property double nowMs: Date.now()
    property Timer stampTick: Timer {
        interval: 30000
        repeat: true
        triggeredOnStart: true
        running: svc.items.length > 0 || svc.toasts.length > 0
        onTriggered: svc.nowMs = Date.now()
    }

    function isExpanded(app) {
        return svc.expandedApps[app] === true;
    }
    function toggleExpanded(app) {
        var m = {};
        for (var k in svc.expandedApps)
            m[k] = svc.expandedApps[k];
        m[app] = !m[app];
        svc.expandedApps = m;
    }
    function dismissApp(app) {
        var snap = svc.items.slice();
        for (var i = 0; i < snap.length; i++)
            if (svc.keyOf(snap[i]) === app)
                snap[i].dismiss();
    }
    function removeToastApp(app) {
        svc.toasts = svc.toasts.filter(function (n) {
            return svc.keyOf(n) !== app;
        });
        svc._pruneToastExpiry();
    }

    property NotificationServer server: NotificationServer {
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        inlineReplySupported: true
        onNotification: function (notification) {
            notification.tracked = true; // keep the object alive past this handler
            svc._stamp(notification);
            svc.addItem(notification);
            if (!svc.dnd && !svc.screencasting)
                svc.pushToast(notification);
            notification.closed.connect(function () {
                svc.removeItem(notification);
                svc.removeToast(notification);
            });
        }
    }

    function addItem(n) {
        var l = svc.items.slice();
        l.unshift(n);
        // Cap the persistent list so a chatty or never-dismissed app can't grow it
        // (and the decoded images its Notifications retain) without bound; keep the
        // newest 100. Dropped items aren't dismiss()ed -- just released from our
        // array. (Toasts cap at 8 in pushToast.)
        if (l.length > 100)
            l = l.slice(0, 100);
        svc.items = l;
        svc._pruneSeenAt();
    }
    function removeItem(n) {
        svc.items = svc.items.filter(function (x) {
            return x !== n;
        });
        // Drop expand state for apps that no longer have any notifications, so the
        // map cannot grow without bound and a returning app is not stale-expanded.
        var present = {};
        for (var i = 0; i < svc.items.length; i++)
            present[svc.keyOf(svc.items[i])] = true;
        var m = {};
        for (var k in svc.expandedApps)
            if (present[k])
                m[k] = svc.expandedApps[k];
        svc.expandedApps = m;
        svc._pruneSeenAt();
    }
    function pushToast(n) {
        var t = svc.toasts.slice();
        t.unshift(n);
        if (t.length > 8)
            t = t.slice(0, 8);
        svc.toasts = t;
        if (n.urgency !== NotificationUrgency.Critical)
            svc.setExpiry(n, Date.now() + svc.toastTimeoutMs);
    }
    function removeToast(n) {
        svc.toasts = svc.toasts.filter(function (x) {
            return x !== n;
        });
        svc._pruneToastExpiry();
    }
    // Keep toastExpiry to only the ids still present in `toasts` -- otherwise the
    // map accumulates one entry per notification ever shown.
    function _pruneToastExpiry() {
        var live = {};
        for (var i = 0; i < svc.toasts.length; i++)
            live[svc.toasts[i].id] = true;
        var e = {};
        for (var k in svc.toastExpiry)
            if (live[k])
                e[k] = svc.toastExpiry[k];
        svc.toastExpiry = e;
    }
    function dismissAll() {
        var l = svc.items.slice();
        for (var i = 0; i < l.length; i++)
            l[i].dismiss(); // closed handlers clear items/toasts
    }
}
