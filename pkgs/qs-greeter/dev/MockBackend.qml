import QtQuick
import Quickshell.Io

// Scripted stand-in for greetd. NEVER installed: pkgs/qs-greeter/default.nix
// takes greeter/ as its src, so dev/ cannot reach a deployed system.
QtObject {
    id: root

    readonly property bool available: true
    property int respondCount: 0
    property int cancelCount: 0
    property var scenario: null
    property int _stepIndex: 0
    // Every Timer _fire() creates, so an abandoned scenario's still-pending
    // steps can be stopped and destroyed instead of firing into whatever
    // scenario runs next. Without this, a step from a scenario that was
    // cancelled or replaced can still deliver its signal late and corrupt an
    // unrelated later assertion -- exactly the kind of cross-test
    // contamination that is miserable to diagnose from a flaky run.
    property var _timers: []

    signal authMessage(string message, bool error, bool responseRequired, bool echoResponse)
    signal authFailure(string message)
    signal readyToLaunch()
    signal launched()
    signal error(string message)

    function loadScenario(name) {
        _killTimers();
        var path = Qt.resolvedUrl("scenarios/" + name + ".json");
        var xhr = new XMLHttpRequest();
        xhr.open("GET", path, false);
        xhr.send();
        root.scenario = JSON.parse(xhr.responseText);
        root._stepIndex = 0;
        root.respondCount = 0;
        root.cancelCount = 0;
    }

    function createSession(user) { _runFrom(0, 0); }

    function respond(text) {
        root.respondCount++;
        _runFrom(root._stepIndex, root.respondCount);
    }

    function cancelSession() {
        _killTimers();
        root.cancelCount++;
        root._stepIndex = 0;
    }

    function _killTimers() {
        for (var i = 0; i < root._timers.length; i++) {
            var t = root._timers[i];
            t.stop();
            t.destroy();
        }
        root._timers = [];
    }

    // Launch is inert by design. A mock that could start a session would be a
    // login bypass with extra steps.
    function launch(argv, env, quit) {
        console.log("MOCK launch (inert): " + JSON.stringify(argv));
        root.launched();
    }

    // Sequential-with-pause: fire steps in order starting at `index`. On
    // reaching a step gated by onRespond that the current respondCount does
    // not satisfy, STOP (do not skip past it) and leave _stepIndex pointing
    // at that step, so the next respond() resumes exactly there. Skipping
    // past an unmet gate (as `continue` would) lets a later ungated step
    // fire out of order and strands the gated step unreachable forever.
    function _runFrom(index, respondCount) {
        var steps = (root.scenario && root.scenario.steps) || [];
        for (var i = index; i < steps.length; i++) {
            var s = steps[i];
            if (s.onRespond !== undefined && s.onRespond !== respondCount) break;
            root._stepIndex = i + 1;
            _fire(s);
        }
    }

    function _fire(step) {
        var t = Qt.createQmlObject(
            'import QtQuick; Timer { repeat: false }', root);
        t.interval = step.after || 0;
        root._timers.push(t);
        t.triggered.connect(function () {
            var idx = root._timers.indexOf(t);
            if (idx >= 0) root._timers.splice(idx, 1);
            if (step.authMessage) {
                var m = step.authMessage;
                root.authMessage(m.message, !!m.error, !!m.responseRequired, !!m.echoResponse);
            }
            if (step.authFailure) root.authFailure(step.authFailure);
            if (step.readyToLaunch) root.readyToLaunch();
            if (step.error) root.error(step.error);
            t.destroy();
        });
        t.start();
    }
}
