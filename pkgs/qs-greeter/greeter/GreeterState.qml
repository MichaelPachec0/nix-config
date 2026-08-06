pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Greeter-written state, deliberately a separate file from settings: the
// greeter writes this and the user writes the other, so neither can corrupt
// the other, and a corrupt state file costs only a prefilled username.
//
// Named GreeterState, not State: QtQuick already ships a built-in `State`
// element (property-state-machine states), and a same-named singleton is
// silently shadowed by it everywhere `import QtQuick` is in scope -- i.e.
// everywhere. Confirmed the hard way while wiring this up: the brief's own
// interface names it State.save(), and calling that resolved to QtQuick's
// State and threw "Property 'save' of object QtQuick/State is not a
// function" instead of ever reaching this file's singleton.
//
// The plan's brief sketched the write as `Process { command: ["sh", "-c",
// "printf '%s' " + Qt.btoa(JSON.stringify({...})) + " | base64 -d > '" +
// root.path + "'"] }`. That construction is arguably safe on its own terms
// -- the one value in it that is attacker-adjacent (the typed username)
// never reaches the shell as raw text; it is folded into JSON and then
// base64 first, and base64's output alphabet (A-Za-z0-9+/=) contains no
// shell metacharacter, so it cannot break out of the unquoted printf
// argument no matter what the username contains. But "safe by an argument
// about a specific alphabet" is a strictly worse property than "there is no
// shell to make an argument about" -- every other value this file writes
// (lastSession, and root.path itself) would still need the same argument
// re-made by hand for every future edit, and a shell in the write path at
// all is a needless surface for the next person touching this file to get
// wrong. FileView.writeAdapter() writes the file directly: no /bin/sh, no
// string interpolation, no quoting to reason about. This is also not a new
// idiom invented for this file -- it is the exact FileView+JsonAdapter
// pattern this repo already uses for its other disk-persisted UI state
// (see lib/CalState.qml and lib/InhibitService.qml under
// features/hm/wayland/quickshell/task-bar/), so this is the well-trodden
// path here, not the novel one.
Singleton {
    id: root
    readonly property string path: Quickshell.env("QSG_STATE_FILE")
        || "/var/lib/qs-greeter/state.json"

    property alias lastUser: adapter.lastUser
    property alias lastSession: adapter.lastSession

    // Persist once, after the caller has already set both properties (the
    // logon dialog sets lastUser and lastSession, then calls save()). There
    // is deliberately no `onAdapterUpdated: writeAdapter()` auto-persist
    // hook: that fires per property change, so a caller setting two
    // properties back-to-back would round-trip the adapter mid-update and
    // can revert the first change with a write that only reflects the
    // second -- see InhibitService.qml's _write() for the same rule,
    // reached the hard way there.
    function save() { file.writeAdapter(); }

    FileView {
        id: file
        path: root.path
        Component.onCompleted: reload()

        JsonAdapter {
            id: adapter
            property string lastUser: ""
            property string lastSession: ""
        }
    }
}
