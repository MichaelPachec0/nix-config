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
        if (t.length > 5)
            t = t.slice(0, 5);
        svc.toasts = t;
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
