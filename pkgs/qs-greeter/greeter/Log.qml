pragma Singleton
import QtQuick
import Quickshell

// Leveled logging with one hard rule enforced by construction: this singleton
// has no method that takes a credential, and callers must never pass one. PAM
// prompt text and its flags are logged; typed input is not. Pre-auth logs are
// long-lived, so a debug flag must never become a password dump.
Singleton {
    id: root

    // 0 none, 1 info, 2 debug. Set from QSG_LOG_LEVEL by the module.
    readonly property int level: parseInt(Quickshell.env("QSG_LOG_LEVEL") || "2", 10)

    function debug(msg) { if (level >= 2) console.log("qs-greeter D " + msg); }
    function info(msg)  { if (level >= 1) console.log("qs-greeter I " + msg); }
    function warn(msg)  { console.warn("qs-greeter W " + msg); }
    function error(msg) { console.error("qs-greeter E " + msg); }
}
