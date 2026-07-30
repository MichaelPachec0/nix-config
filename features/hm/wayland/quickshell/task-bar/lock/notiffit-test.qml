// features/hm/wayland/quickshell/task-bar/lock/notiffit-test.qml
// Unit test for LockNotifications' dynamic height fit (`_cardHeight` /
// `_fitCount`). Run headless:
//
//   quickshell -p features/hm/wayland/quickshell/task-bar/lock/notiffit-test.qml
//
// Expect a single "FIT-TEST PASS n/n" line and exit.
//
// This file is a SIBLING of the component on purpose: `qs -p` sandboxes imports
// to the entrypoint's parent directory, so `import "../"` is blocked and a bare
// type name is the only way to resolve LockNotifications (same reason as
// notifpolicy-test.qml).
//
// Why this test exists: the fit had to be a PURE function of the model, because
// the measure-the-rendered-cards version was a binding loop that wedged a live
// lock. Being pure is exactly what makes it testable with no window, so keep it
// that way -- if this test ever needs a rendered surface to pass, the fit has
// regressed into measuring the layout again.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

ShellRoot {
    // Rules chosen so classification is trivial and the arithmetic below is
    // about GEOMETRY, not policy: every Normal notification is `sensitive`,
    // every Critical one `full`, "Secret" is always `hidden`, and "Trusted"
    // is the one app that can produce an interactive card.
    LockNotifyPolicy {
        id: pol
        trustedApps: ["Trusted"]
        privateApps: ["Secret"]
        trustedCategories: []
        defaultMode: "sensitive"
    }

    LockNotifications {
        id: nl
        policy: pol
        theme: null
    }

    // Duck-typed Notification. Only the fields the policy and the height model
    // actually read.
    function mock(o) {
        return {
            id: o.id === undefined ? 0 : o.id,
            appName: o.appName || "",
            desktopEntry: o.desktopEntry || "",
            summary: o.summary || "s",
            body: o.body || "",
            image: o.image || "",
            urgency: o.urgency === undefined ? NotificationUrgency.Normal : o.urgency,
            actions: o.actions || [],
            hints: o.hints || ({}),
            _stack: o.stack,
            _newest: o.newest
        };
    }

    // Build a `groups`-shaped payload ([{app, list}]) from (app, count) pairs.
    function groupsOf(specs) {
        return specs.map(function (sp) {
            var list = [];
            for (var i = 0; i < sp.n; i++)
                list.push(mock({ id: sp.app + i, appName: sp.app, urgency: sp.urgency, body: sp.body, image: sp.image, actions: sp.actions, stack: sp.stack, newest: sp.newest }));
            return { app: sp.app, list: list };
        });
    }

    // Mock stacking: ONE stack per notification, with the count/newest the case
    // asked for. Grouping itself is covered by lib/notifstack-test.qml, so
    // reimplementing it here would only risk the two drifting apart.
    function fakeStacksOf(list) {
        return list.map(function (n) {
            return {
                key: String(n.id),
                list: [n],
                count: n._stack === undefined ? 1 : n._stack,
                newest: n._newest === undefined ? 0 : n._newest,
                oldest: n._newest === undefined ? 0 : n._newest
            };
        });
    }

    function feed(specs, avail, hideAll, ceiling) {
        nl.maxCards = ceiling === undefined ? 0 : ceiling;
        nl.hideAll = !!hideAll;
        nl.availableHeight = avail;
        nl.notifications = { groups: groupsOf(specs), stacksOf: fakeStacksOf, nowMs: 0 };
    }

    // Wrap one mock notification as a single-member stack.
    function st1(o) {
        return { key: "k", list: [mock(o)], count: o.stack === undefined ? 1 : o.stack,
                 newest: o.newest === undefined ? 0 : o.newest,
                 oldest: o.newest === undefined ? 0 : o.newest };
    }

    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (got === want)
                pass++;
            else
                console.log("FIT-TEST CASE FAIL: " + name + " got=" + got + " want=" + want);
        }

        // Guard: the component self-disables when notifications are switched
        // off in config, which would make every count below 0 for the wrong
        // reason.
        if (!LockConfig.notifEnable)
            console.log("FIT-TEST WARN: LockConfig.notifEnable is false; counts will be 0");

        // ---- the height model -------------------------------------------
        // Constants: pad 12 + summary 18 = 30 for a sensitive card. A full card
        // adds spacing 3 + 16/body line (<=4 lines, ~40 chars per line), then
        // +3+64 for a thumb and +3+19 for an action row.
        var CRIT = NotificationUrgency.Critical;
        check("h/sensitive", nl._cardHeight(st1({ appName: "A", body: "ignored below full" })), 30);
        check("h/hidden", nl._cardHeight(st1({ appName: "Secret", body: "x" })), 0);
        check("h/full-1line", nl._cardHeight(st1({ appName: "A", urgency: CRIT, body: "short" })), 12 + 18 + 3 + 16);
        check("h/full-nobody", nl._cardHeight(st1({ appName: "A", urgency: CRIT, body: "" })), 30);
        // 100 chars -> ceil(100/40) = 3 lines
        var b100 = new Array(101).join("x");
        check("h/full-3line", nl._cardHeight(st1({ appName: "A", urgency: CRIT, body: b100 })), 12 + 18 + 3 + 48);
        // 400 chars -> clamped to maximumLineCount 4
        var b400 = new Array(401).join("x");
        check("h/full-clamped", nl._cardHeight(st1({ appName: "A", urgency: CRIT, body: b400 })), 12 + 18 + 3 + 64);
        check("h/full-thumb", nl._cardHeight(st1({ appName: "A", urgency: CRIT, body: b100, image: "/tmp/x.png" })), 12 + 18 + 3 + 48 + 3 + 64);
        check("h/full-actions", nl._cardHeight(st1({ appName: "A", urgency: CRIT, body: b100, actions: [{ text: "go" }] })), 12 + 18 + 3 + 48 + 3 + 19);
        // Meta row: charged once when the card carries a count and/or a stamp.
        check("h/meta-count", nl._cardHeight(st1({ appName: "A", stack: 3 })), 30 + 3 + 15);
        check("h/meta-stamp", nl._cardHeight(st1({ appName: "A", newest: 1000 })), 30 + 3 + 15);
        check("h/meta-both", nl._cardHeight(st1({ appName: "A", stack: 3, newest: 1000 })), 30 + 3 + 15);
        check("h/meta-none", nl._cardHeight(st1({ appName: "A" })), 30);

        // The strictest-tier backstop: a stack whose members would classify
        // DIFFERENTLY must render at the tightest tier, and must expose no
        // action. Both mocks elsewhere build single-member stacks, so this is
        // the only case that exercises _classifyStack's reduction loop -- the
        // guard that has to survive future drift in notifstack.js's key.
        var mixed = { key: "k", list: [mock({ appName: "A" }), mock({ appName: "Secret" })],
                      count: 2, newest: 0, oldest: 0 };
        check("cls/strictest-hidden", nl._visOf(mixed), "hidden");

        // The interactive conjunct: the NEWEST member here is trusted AND has an
        // action, so `newest.interactive` is true on its own. The stack must
        // still expose NO action, because another member is private and drags
        // the whole stack to the hidden tier. This is what gates a no-PAM action
        // button on a locked screen, so it must be covered by a case that would
        // FAIL if the `worst.visibility === "full" &&` conjunct were dropped.
        var mixedTrusted = { key: "k2",
                             list: [mock({ appName: "Trusted", actions: [{ text: "go" }] }),
                                    mock({ appName: "Secret" })],
                             count: 2, newest: 0, oldest: 0 };
        // Guard the guard: confirm the newest member really is interactive on
        // its own, so the assertion below cannot go vacuous again if the
        // fixture's trust rules ever change.
        check("cls/newest-is-interactive", pol.classify(mixedTrusted.list[0], false).interactive, true);
        check("cls/strictest-noactions", nl._classifyStack(mixedTrusted).interactive, false);

        // ---- the fit ------------------------------------------------------
        // budget = availableHeight - (header 22 + spacing 8) - (footer 18 + spacing 8)
        //        = availableHeight - 56
        // A sensitive card costs 30 + groupSpacing 4 = 34; the first card of a
        // group also pays groupHead 20 (+ spacing 8 when it is not the first
        // row of all).
        feed([{ app: "Alpha", n: 5 }], 1000);
        check("fit/roomy", nl._fitCount, 5);
        check("overflow/roomy", nl._overflow, 0);

        // 150 -> budget 94: 54 (head+card) + 34 = 88 fits, +34 = 122 does not.
        feed([{ app: "Alpha", n: 5 }], 150);
        check("fit/tight", nl._fitCount, 2);
        check("overflow/tight", nl._overflow, 3);

        // Too small for even one card: degrade to zero cards, never overlap.
        feed([{ app: "Alpha", n: 5 }], 60);
        check("fit/none", nl._fitCount, 0);
        check("overflow/none", nl._overflow, 5);

        // Second group pays another group header (20) + inter-group spacing (8).
        feed([{ app: "Alpha", n: 2 }, { app: "Beta", n: 2 }], 1000);
        check("fit/two-groups", nl._fitCount, 4);
        // 54 + 34 + (20+8+34) = 150 -> budget 150 needs availableHeight 206.
        feed([{ app: "Alpha", n: 2 }, { app: "Beta", n: 2 }], 206);
        check("fit/two-groups-exact", nl._fitCount, 3);

        // Unbounded budget falls back to the ceiling alone.
        feed([{ app: "Alpha", n: 5 }], 0);
        check("fit/unbounded", nl._fitCount, 5);
        feed([{ app: "Alpha", n: 5 }], 0, false, 2);
        check("fit/ceiling", nl._fitCount, 2);
        // The ceiling still caps a roomy budget.
        feed([{ app: "Alpha", n: 5 }], 1000, false, 3);
        check("fit/ceiling-caps", nl._fitCount, 3);

        // hideAll: every card collapses to the group's "N hidden" line, so the
        // list costs almost nothing and nothing is dropped as "+N more".
        feed([{ app: "Alpha", n: 5 }], 150, true);
        check("fit/hideall", nl._fitCount, 5);
        check("overflow/hideall", nl._overflow, 0);

        // Tall full-tier cards are charged their real height, so far fewer fit
        // in the same budget than sensitive ones would. One clamped-body card
        // costs 97 + groupSpacing 4 + groupHead 20 = 121, so the 94 left by a
        // 150px budget is not enough for even one -- where two sensitive cards
        // fitted above.
        feed([{ app: "Alpha", n: 5, urgency: CRIT, body: b400 }], 150);
        check("fit/tall-full-none", nl._fitCount, 0);
        // 200 -> budget 144: one card (121) fits, a second (+101) does not.
        feed([{ app: "Alpha", n: 5, urgency: CRIT, body: b400 }], 200);
        check("fit/tall-full-one", nl._fitCount, 1);

        // Stacking buys budget: 5 separate sensitive cards need 5 card slots,
        // but one x5 stack needs one (plus its meta row), so the same budget
        // covers all 5 notifications instead of dropping 3.
        feed([{ app: "Alpha", n: 5 }], 150);
        check("fit/unstacked-drops", nl._overflow, 3);
        feed([{ app: "Alpha", n: 1, stack: 5 }], 150);
        check("fit/stacked-keeps", nl._overflow, 0);
        check("fit/stacked-one-card", nl._fitCount, 1);

        console.log(pass === total ? ("FIT-TEST PASS " + pass + "/" + total)
                                   : ("FIT-TEST FAIL " + pass + "/" + total));
        Qt.quit();
    }
}
