import QtQuick
import Quickshell.Services.Greetd

// Thin adapter so Session can be driven by a mock in development. The mock
// lives in dev/, which is NOT part of the installed derivation, so no runtime
// mistake can substitute it on a deployed system.
QtObject {
    id: root

    readonly property bool available: Greetd.available

    signal authMessage(string message, bool error, bool responseRequired, bool echoResponse)
    signal authFailure(string message)
    signal readyToLaunch()
    signal launched()
    signal error(string message)

    function createSession(user) { Greetd.createSession(user); }
    // Only ever called for visible/secret prompts. greetd requires an ack for
    // info and error messages too, but quickshell sends that itself
    // (services/greetd/connection.cpp: if (!responseRequired) sendRequest(...)),
    // and respond() logs a critical if no response is pending.
    function respond(text) { Greetd.respond(text); }
    function cancelSession() { Greetd.cancelSession(); }
    function launch(argv, env, quit) { Greetd.launch(argv, env, quit); }

    property var _c: Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            root.authMessage(message, error, responseRequired, echoResponse);
        }
        function onAuthFailure(message) { root.authFailure(message); }
        function onReadyToLaunch() { root.readyToLaunch(); }
        function onLaunched() { root.launched(); }
        function onError(message) { root.error(message); }
    }
}
