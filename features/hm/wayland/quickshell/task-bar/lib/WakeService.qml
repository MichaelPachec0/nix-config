import QtQuick
import Quickshell
import Quickshell.Io

// Publishes the system's last resume, so widgets can refresh what suspending
// made stale. The stamp is written by the NixOS resume hook
// (powerManagement.resumeCommands in features/nixos/desktop/common) into
// /run/qs-wake/stamp, containing the wake time in epoch seconds.
//
// Hoisted to ShellRoot and passed by reference. The ShellRoot id MUST differ
// from the property name it feeds -- a same-name binding across the Variants
// delegate resolves to the child's own null property (see the shell.qml
// submapSvc note).
//
// Holds nothing sensitive: the file is a single timestamp, world-readable by
// design so any session tool can compare a cache against it.
Scope {
    id: root

    // Overridable so a harness can point at a fixture instead of /run.
    property string stampPath: "/run/qs-wake/stamp"

    // Epoch seconds of the last resume; 0 until one is read. /run is a tmpfs,
    // so an absent file means "no resume since this boot" -- a normal state,
    // not an error, and deliberately NOT reported as a wake.
    property int stamp: 0

    // Set once any stamp has been read. The first read never emits woke():
    // starting the shell on a machine that resumed earlier would otherwise
    // announce a wake that happened before this process existed.
    property bool seen: false

    signal woke

    FileView {
        id: file
        path: root.stampPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        Component.onCompleted: reload()
        onLoaded: {
            var v = parseInt(String(file.text()).trim(), 10);
            // Ignore junk rather than treating it as a wake. A half-written
            // file should be impossible -- the hook renames into place -- but
            // parsing "" to NaN and firing on it would be a self-inflicted
            // refresh loop.
            if (isNaN(v) || v <= 0)
                return;
            if (v === root.stamp)
                return;
            var first = !root.seen;
            root.seen = true;
            root.stamp = v;
            if (!first)
                root.woke();
        }
    }

    // The hook writes the stamp by renaming a temp file into place, which
    // replaces the inode a plain watch is attached to -- the same reason
    // RouterService polls its artifact rather than trusting onFileChanged.
    // Slow: a resume is rare and a few seconds late costs nothing, where a
    // 2s tick for the whole session would be pure waste.
    Timer {
        running: true
        interval: 5000
        repeat: true
        onTriggered: file.reload()
    }
}
