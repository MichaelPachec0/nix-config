// features/hm/wayland/quickshell/task-bar/lock/LockSecurity.qml
// Security and presence signals, top-left on the lock. Every value here is
// METADATA -- counts, times, session numbers -- so unlike the notification list
// there is no content to tier or gate. Do not add anything that renders a
// message, a title, or a filename without revisiting that.
//
// The rows that matter stay HIDDEN until they fire; a row that is always present
// becomes wallpaper. Uptime and last-unlock are the deliberate exceptions.
//
// `stampFn` is injected rather than imported (LockSurface passes
// NotifTime.fmtStamp) because `import "../lib/notiftime.js"` fails when
// locksec-test.qml is the quickshell -p entrypoint -- the entrypoint's parent
// becomes the config root. Same pattern as LockNotifications.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    property var theme: null
    property real contentOpacity: 1.0

    // --- inputs -----------------------------------------------------------
    property bool castAtLock: false   // a capture was already running at lock
    property var casts: null          // int from the poll, or null = could not ask
    property bool pollEnabled: true   // LockConfig.secScreencastPoll
    // False until the first probe result arrives. Without this the "unknown"
    // warning would flash on EVERY lock during the pre-first-poll window, and a
    // warning that appears routinely is one the user stops reading.
    property bool probed: false
    property int fails: 0
    property int otherUsers: 0
    property int uptimeSec: 0
    property double lastUnlockMs: 0
    property string ownerText: ""
    property bool showUptime: true
    property bool showLastUnlock: true
    property var stampFn: null
    property double nowMs: 0
    property bool hour12: false

    spacing: 4
    opacity: root.contentOpacity

    // --- derived state (pure; covered by locksec-test.qml) ----------------
    // A capture detected either way. `casts > 0` is only meaningful when the
    // poll actually answered, hence the explicit null check.
    readonly property bool sharing: root.castAtLock || (root.casts !== null && root.casts > 0)

    // "Could not ask" -- shown ONLY when the poll is enabled, has answered at
    // least once, and has no answer, and nothing was detected. `probed` gates
    // out the first moments of every lock, when the poll simply has not run
    // yet (CommandPoll.value starts null); without it this would flash on
    // every lock. With the poll off, `casts` is permanently null, so without
    // the pollEnabled term switching the poll off would pin this warning on
    // screen forever, which is the opposite of what opting out means.
    readonly property bool sharingUnknown: root.pollEnabled && root.probed && root.casts === null && !root.sharing

    function _fmtUptime(sec) {
        var s = Math.max(0, Math.floor(sec));
        if (s < 60)
            return "just booted";
        var m = Math.floor(s / 60);
        if (m < 60)
            return m + "m";
        var h = Math.floor(m / 60);
        if (h < 24)
            return h + "h " + (m % 60) + "m";
        return Math.floor(h / 24) + "d " + (h % 24) + "h";
    }
    function _failText(n) { return n + (n === 1 ? " failed attempt" : " failed attempts"); }
    function _sessionText(n) { return n + (n === 1 ? " other session" : " other sessions"); }

    // A missing stamp must read as unknown, never as a formatted zero epoch.
    readonly property string lastUnlockText: {
        if (!(root.lastUnlockMs > 0) || !root.stampFn)
            return "Last unlock unknown";
        var s = root.stampFn(root.nowMs, root.lastUnlockMs, root.hour12);
        return s.length > 0 ? ("Last unlock " + s) : "Last unlock unknown";
    }

    // --- rows -------------------------------------------------------------
    // NB: the children address the row through its own `id`, not `parent`.
    // Both resolve here, but this repo has already lost time to QML name
    // resolution picking up an enclosing scope, and an explicit id cannot.
    component SignalRow: RowLayout {
        id: rowRoot
        property string glyph: ""
        property string label: ""
        property color tint: root.theme ? root.theme.textSecondary : "#a89984"
        property real rowOpacity: 1.0
        // `ownerText` is arbitrary user-configured free text with no length
        // validation anywhere in the chain; without a cap a long value grows
        // this top-left-anchored column rightward toward the centred password
        // field. 320 matches the password field's width. Pattern mirrors
        // LockNotifications.qml's text constraint.
        Layout.maximumWidth: 320
        spacing: 6
        LockText {
            text: rowRoot.glyph
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            color: rowRoot.tint
            opacity: rowRoot.rowOpacity
        }
        LockText {
            Layout.fillWidth: true
            text: rowRoot.label
            elide: Text.ElideRight
            font.pixelSize: 12
            color: rowRoot.tint
            opacity: rowRoot.rowOpacity
        }
    }

    SignalRow {
        visible: root.sharing
        glyph: String.fromCodePoint(0xF06E)   // eye
        label: "Screen is being shared"
        tint: root.theme ? root.theme.accentRed : "#fb4934"
    }
    SignalRow {
        visible: root.sharingUnknown
        glyph: String.fromCodePoint(0xF071)   // warning triangle
        label: "Sharing state unknown"
        tint: root.theme ? root.theme.accentYellow : "#fabd2f"
    }
    SignalRow {
        visible: root.fails > 0
        glyph: String.fromCodePoint(0xF023)   // lock
        label: root._failText(root.fails)
        tint: root.theme ? root.theme.accentRed : "#fb4934"
    }
    SignalRow {
        visible: root.otherUsers > 0 && root.probed
        glyph: String.fromCodePoint(0xF0C0)   // users
        label: root._sessionText(root.otherUsers)
        tint: root.theme ? root.theme.accentRed : "#fb4934"
    }
    SignalRow {
        visible: root.showLastUnlock
        glyph: String.fromCodePoint(0xF13E)   // unlock
        label: root.lastUnlockText
    }
    SignalRow {
        visible: root.showUptime && root.probed
        glyph: String.fromCodePoint(0xF017)   // clock
        label: "Up " + root._fmtUptime(root.uptimeSec)
    }
    SignalRow {
        visible: root.ownerText.length > 0
        glyph: String.fromCodePoint(0xF2C0)   // user card
        label: root.ownerText
        rowOpacity: 0.7
    }
}
