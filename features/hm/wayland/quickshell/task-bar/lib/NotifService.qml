import QtQuick
import Quickshell.Services.Notifications

// Global notification service: owns the Quickshell NotificationServer (acquires
// org.freedesktop.Notifications, replacing swaync) and maintains two reactive
// lists -- `items` (persistent, for the hub card) and `toasts` (transient, for
// the popup overlay). Both hold the same Notification objects with different
// lifetimes. DND suppresses new toasts; notifications still land in `items`.
// Instantiated once at the ShellRoot level.
//
// We keep our own arrays rather than binding to server.trackedNotifications
// because that model's value-changes don't drive QML bindings reactively; here
// reassigning the arrays does. Each notification is removed on its `closed`
// signal (dismissed, expired, or replaced).
QtObject {
    id: svc

    property bool dnd: false
    property var items: []  // persistent (newest first)
    property var toasts: [] // transient popups (newest first)

    readonly property int count: svc.items.length

    // Per-app grouping (derived). Newest group first, newest card first.
    readonly property var groups: svc.groupBy(svc.items)
    readonly property var toastGroups: svc.groupBy(svc.toasts)

    // Expand/collapse state per app, kept here so it survives model rebuilds.
    property var expandedApps: ({})

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
    }

    property NotificationServer server: NotificationServer {
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        onNotification: function (notification) {
            notification.tracked = true; // keep the object alive past this handler
            svc.addItem(notification);
            if (!svc.dnd)
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
        svc.items = l;
    }
    function removeItem(n) {
        svc.items = svc.items.filter(function (x) {
            return x !== n;
        });
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
    }
    function dismissAll() {
        var l = svc.items.slice();
        for (var i = 0; i < l.length; i++)
            l[i].dismiss(); // closed handlers clear items/toasts
    }
}
