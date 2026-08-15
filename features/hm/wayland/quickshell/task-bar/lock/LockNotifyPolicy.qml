// features/hm/wayland/quickshell/task-bar/lock/LockNotifyPolicy.qml
// Lock-only notification classifier. Pure: classify(n, hideAll) maps a
// notification to {tier, visibility, interactive}. Rule inputs default to the
// Nix-driven LockConfig but are overridable (for tests). See
// docs/lock-notifications/spec.md.
import QtQuick
import Quickshell.Services.Notifications

QtObject {
    id: policy

    // Rules are INJECTED by the caller (Lock.qml binds these to LockConfig in
    // Task 3). Plain defaults keep the classifier decoupled from LockConfig and
    // unit-testable via `qs -p` without the config singleton.
    property var trustedApps: []
    property var privateApps: []
    property var trustedCategories: []
    property string defaultMode: "sensitive" // "sensitive"|"hidden"|"full"

    // case-insensitive glob (only '*' is special)
    function _glob(pat, s) {
        if (pat === undefined || pat === null || s === undefined || s === null || s === "")
            return false;
        var esc = String(pat).replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
        return new RegExp("^" + esc + "$", "i").test(String(s));
    }
    function _matchesAny(list, vals) {
        if (!list)
            return false;
        for (var i = 0; i < list.length; i++)
            for (var j = 0; j < vals.length; j++)
                if (policy._glob(list[i], vals[j]))
                    return true;
        return false;
    }

    function classify(n, hideAll) {
        var appVals = [n.desktopEntry, n.appName];
        var cat = (n.hints && n.hints["category"]) ? n.hints["category"] : "";

        var tier;
        if (policy._matchesAny(policy.privateApps, appVals))
            tier = "private";
        else if (policy._matchesAny(policy.trustedApps, appVals))
            tier = "trusted";
        else if (policy._matchesAny(policy.trustedCategories, [cat]))
            tier = "trusted";
        else
            tier = "default";

        // visibility precedence: hideAll > private > Critical > trusted > mode
        var visibility;
        if (hideAll)
            visibility = "hidden";
        else if (tier === "private")
            visibility = "hidden";
        else if (n.urgency === NotificationUrgency.Critical)
            visibility = "full";
        else if (tier === "trusted")
            visibility = "full";
        else
            visibility = policy.defaultMode;

        var interactive = (tier === "trusted") && !hideAll && !!(n.actions && n.actions.length > 0);

        return { tier: tier, visibility: visibility, interactive: interactive };
    }
}
