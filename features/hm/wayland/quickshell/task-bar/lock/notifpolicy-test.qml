import QtQuick
import Quickshell
import Quickshell.Services.Notifications

ShellRoot {
    LockNotifyPolicy {
        id: p
        trustedApps: ["blueman", "org.freedesktop.*"]
        privateApps: ["Signal"]
        trustedCategories: ["device", "x-systemd*"]
        defaultMode: "sensitive"
    }
    function mock(o) {
        // minimal duck-typed notification
        return {
            appName: o.appName || "", desktopEntry: o.desktopEntry || "",
            urgency: o.urgency === undefined ? NotificationUrgency.Normal : o.urgency,
            actions: o.actions || [], hints: o.hints || ({})
        };
    }
    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (JSON.stringify(got) === JSON.stringify(want)) { pass++; }
            else console.log("POLICY-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
        }
        // default tier -> sensitive, not interactive
        check("default", p.classify(mock({appName: "Discord", actions: [{text: "x"}]}), false),
              {tier: "default", visibility: "sensitive", interactive: false});
        // trusted by app -> full + interactive (has actions)
        check("trustedApp", p.classify(mock({appName: "blueman", actions: [{text: "Yes"}]}), false),
              {tier: "trusted", visibility: "full", interactive: true});
        // trusted by desktopEntry glob -> full
        check("trustedGlob", p.classify(mock({desktopEntry: "org.freedesktop.NetworkManager"}), false),
              {tier: "trusted", visibility: "full", interactive: false});
        // trusted by category -> full
        check("trustedCat", p.classify(mock({appName: "sys", hints: {category: "device"}, actions: [{text: "a"}]}), false),
              {tier: "trusted", visibility: "full", interactive: true});
        // private app -> hidden, never interactive, even Critical
        check("privateCritical", p.classify(mock({appName: "Signal", urgency: NotificationUrgency.Critical, actions: [{text: "r"}]}), false),
              {tier: "private", visibility: "hidden", interactive: false});
        // critical non-private, non-trusted -> full but NOT interactive
        check("criticalDefault", p.classify(mock({appName: "Mail", urgency: NotificationUrgency.Critical}), false),
              {tier: "default", visibility: "full", interactive: false});
        // hideAll overrides everything incl trusted
        check("hideAll", p.classify(mock({appName: "blueman", actions: [{text: "y"}]}), true),
              {tier: "trusted", visibility: "hidden", interactive: false});
        // trusted but no actions -> not interactive
        check("trustedNoActions", p.classify(mock({appName: "blueman"}), false),
              {tier: "trusted", visibility: "full", interactive: false});
        // defaultMode=full changes default tier visibility
        p.defaultMode = "full";
        check("defaultModeFull", p.classify(mock({appName: "Discord"}), false),
              {tier: "default", visibility: "full", interactive: false});
        console.log("POLICY-TEST " + (pass === total ? "PASS" : "FAIL") + " " + pass + "/" + total);
        Qt.quit();
    }
}
