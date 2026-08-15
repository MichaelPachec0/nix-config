// features/hm/wayland/quickshell/task-bar/lib/notifstack-test.qml
// Unit test for notifstack.js. Run headless:
//   quickshell -p features/hm/wayland/quickshell/task-bar/lib/notifstack-test.qml
// Expect a single "STACK-TEST PASS n/n" line.
import QtQuick
import Quickshell
import "notifstack.js" as S

ShellRoot {
    // Duck-typed Notification: only the fields the key reads, plus id.
    function n(o) {
        return {
            id: o.id,
            appName: o.appName === undefined ? "App" : o.appName,
            desktopEntry: o.desktopEntry === undefined ? "app.desktop" : o.desktopEntry,
            summary: o.summary === undefined ? "Sum" : o.summary,
            body: o.body === undefined ? "Body" : o.body,
            urgency: o.urgency === undefined ? 1 : o.urgency
        };
    }

    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (JSON.stringify(got) === JSON.stringify(want)) pass++;
            else console.log("STACK-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
        }

        // --- stackKey -----------------------------------------------------
        check("key/identical",
              S.stackKey(n({id: 1})) === S.stackKey(n({id: 2})), true);
        check("key/body", S.stackKey(n({id: 1, body: "a"})) === S.stackKey(n({id: 2, body: "b"})), false);
        check("key/summary", S.stackKey(n({id: 1, summary: "a"})) === S.stackKey(n({id: 2, summary: "b"})), false);
        check("key/appName", S.stackKey(n({id: 1, appName: "a"})) === S.stackKey(n({id: 2, appName: "b"})), false);
        // desktopEntry and urgency are in the key because the lock derives its
        // PRIVACY TIER from them -- merging across them could show a private
        // notification's content at a trusted member's tier.
        check("key/desktopEntry", S.stackKey(n({id: 1, desktopEntry: "a"})) === S.stackKey(n({id: 2, desktopEntry: "b"})), false);
        check("key/urgency", S.stackKey(n({id: 1, urgency: 1})) === S.stackKey(n({id: 2, urgency: 2})), false);
        // A field value cannot forge a separator boundary.
        check("key/noCollision",
              S.stackKey(n({id: 1, appName: "a", desktopEntry: "b"})) === S.stackKey(n({id: 2, appName: "a\x1fb", desktopEntry: ""})), false);
        // Delimiter injection: a separator byte inside a field value must not be
        // able to forge a field boundary. Fails on an un-prefixed join.
        check("key/injection",
              S.stackKey(n({id: 1, appName: "a", desktopEntry: "b\x1fc"})) === S.stackKey(n({id: 2, appName: "a\x1fb", desktopEntry: "c"})), false);
        // Missing/null fields are tolerated (a Notification may omit them).
        check("key/nullSafe", typeof S.stackKey({id: 1}) === "string", true);

        // --- stacksOf -----------------------------------------------------
        check("stacks/empty", S.stacksOf([], ({})), []);

        // Three identical -> one stack of 3, members newest-first (input order).
        var three = [n({id: 3}), n({id: 2}), n({id: 1})];
        var st = S.stacksOf(three, ({1: 1000, 2: 2000, 3: 3000}));
        check("stacks/collapseCount", st.length, 1);
        check("stacks/collapseMembers", st[0].count, 3);
        check("stacks/memberOrder", st[0].list.map(function (x) { return x.id; }), [3, 2, 1]);
        check("stacks/newest", st[0].newest, 3000);
        check("stacks/oldest", st[0].oldest, 1000);

        // Differing content -> separate stacks, first-appearance order.
        var mixed = [n({id: 9, body: "b"}), n({id: 8, body: "a"}), n({id: 7, body: "b"})];
        var st2 = S.stacksOf(mixed, ({7: 100, 8: 200, 9: 300}));
        check("stacks/splitCount", st2.length, 2);
        check("stacks/splitFirst", st2[0].list.map(function (x) { return x.id; }), [9, 7]);
        check("stacks/splitSecond", st2[1].list.map(function (x) { return x.id; }), [8]);
        check("stacks/splitOrder", [st2[0].newest, st2[1].newest], [300, 200]);

        // No recorded stamps -> newest/oldest stay 0 (callers render no time).
        var st3 = S.stacksOf([n({id: 5})], ({}));
        check("stacks/noStamp", [st3[0].newest, st3[0].oldest], [0, 0]);
        // A partially-stamped stack still reports the stamps it has.
        var st4 = S.stacksOf([n({id: 6}), n({id: 5})], ({5: 500}));
        check("stacks/partialStamp", [st4[0].newest, st4[0].oldest], [500, 500]);

        console.log(pass === total ? ("STACK-TEST PASS " + pass + "/" + total)
                                   : ("STACK-TEST FAIL " + pass + "/" + total));
        Qt.quit();
    }
}
