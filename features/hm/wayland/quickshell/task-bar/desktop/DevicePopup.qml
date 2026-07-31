import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib" as Lib

// Which devices are capturing and which apps are using them. Opened by a CLICK
// on the media pill's glyph cluster (hover still opens MediaPopup, unchanged).
//
// Kill reuses ProcRow's gesture contract exactly -- left-click arms and swaps
// the label to "end?", a second click sends TERM, Shift+click sends KILL
// immediately -- with arm state keyed by group+pid so it survives the 3s poll's
// model churn without arming two groups' rows for one process at once. ProcRow itself is not reused as a component (its model shape is
// SysPopup-specific), only its contract, so the gesture transfers.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var anchorItem
    required property var barWindow
    required property var capture // Lib.CaptureService
    required property var audio   // Lib.AudioService

    readonly property int cardW: 300

    implicitWidth: pop.cardW
    implicitHeight: Math.max(card.implicitHeight, 1)
    color: "transparent"
    visible: false
    grabFocus: true

    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Right

    function openAt(px) {
        pop.anchor.rect.x = px;
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
        pop.visible = true;
    }
    function toggle() {
        if (pop.visible) {
            pop.visible = false;
            return;
        }
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.openAt(x - pop.cardW / 2);
    }

    // Arm state, keyed by a per-ROW identity rather than by pid or row index.
    //
    // Not the pid: one process can own several rows at once. A browser sharing
    // its screen during a video call holds a mic node AND the cast row under the
    // same pid, and one browser with two call tabs open holds TWO mic nodes,
    // whose rows are identical in every other field. Two rows sharing an arm key
    // means clicking one arms both, so the very next click on the other sends
    // TERM with no confirmation -- the confirmation step silently disappears
    // exactly when the most windows are open.
    //
    // Not the index either: the camera model is rebuilt every 3s and rows can
    // reorder, so an index-keyed arm would jump to a different process between
    // the arming click and the confirming one. Each group therefore supplies
    // something stable and unique to itself -- the PipeWire node id for mics,
    // the device path for cameras.
    property string armedKey: ""
    property Timer disarmTimer: Timer {
        interval: 3000
        onTriggered: pop.armedKey = ""
    }
    function armOrKill(key, pid) {
        // An empty key would collide with the disarmed state and fire on the
        // FIRST click.
        if (!(pid > 0) || key === "")
            return;
        if (pop.armedKey !== key) {
            pop.armedKey = key;
            pop.disarmTimer.restart();
        } else {
            Quickshell.execDetached(["kill", "-TERM", String(pid)]);
            pop.armedKey = "";
        }
    }

    component GroupHeader: RowLayout {
        id: gh
        property string glyph: ""
        property string title: ""
        property string detail: ""
        Layout.fillWidth: true
        spacing: 6
        Text {
            text: gh.glyph
            font.family: pop.theme.iconFont
            font.pixelSize: 12
            color: pop.theme.accentRed
        }
        Text {
            text: gh.title
            font.family: pop.theme.iconFont
            font.pixelSize: 11
            color: pop.theme.textPrimary
        }
        Text {
            Layout.fillWidth: true
            text: gh.detail
            font.family: pop.theme.iconFont
            font.pixelSize: 10
            color: pop.theme.textSecondary
            elide: Text.ElideRight
        }
    }

    // One app row with the arm/kill gesture. `pid <= 0` renders no affordance
    // at all -- a cast attributed only by Hyprland has a title but no process,
    // and a guessed pid is unrecoverable if wrong.
    component AppRow: Item {
        id: ar
        property string appName: ""
        property int pid: 0
        // Identifies THIS row among all rows in the popup (see armedKey).
        property string rowKey: ""
        readonly property bool armed: ar.pid > 0 && ar.rowKey !== "" && ar.rowKey === pop.armedKey
        Layout.fillWidth: true
        implicitHeight: arRow.implicitHeight
        Rectangle {
            anchors.fill: parent
            color: arArea.containsMouse && ar.pid > 0 ? pop.theme.bgItemHover : "transparent"
            radius: 2
        }
        RowLayout {
            id: arRow
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: 18
            }
            Text {
                Layout.fillWidth: true
                text: ar.appName
                font.family: pop.theme.iconFont
                font.pixelSize: 10
                color: pop.theme.textPrimary
                elide: Text.ElideRight
            }
            Text {
                visible: ar.pid > 0
                text: ar.armed ? "end?" : "end"
                font.family: pop.theme.iconFont
                font.pixelSize: 10
                color: ar.armed ? pop.theme.accentRed : pop.theme.textSecondary
            }
        }
        MouseArea {
            id: arArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: ar.pid > 0
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: function (m) {
                if (m.modifiers & Qt.ShiftModifier) {
                    Quickshell.execDetached(["kill", "-KILL", String(ar.pid)]);
                    return;
                }
                pop.armOrKill(ar.rowKey, ar.pid);
            }
        }
    }

    Rectangle {
        id: card
        width: pop.cardW
        implicitHeight: col.implicitHeight + 20
        color: pop.theme.bgCard
        radius: 6
        border.width: 1
        border.color: pop.theme.border

        ColumnLayout {
            id: col
            anchors {
                fill: parent
                margins: 10
            }
            spacing: 6

            // --- camera ---------------------------------------------------
            GroupHeader {
                visible: pop.capture.cameraActive
                glyph: String.fromCodePoint(0xF030)
                title: "Camera"
                detail: pop.capture.cameraActive ? (pop.capture.cameras[0].deviceName || pop.capture.cameras[0].device) : ""
            }
            Repeater {
                model: pop.capture.cameraActive ? pop.capture.cameras : []
                AppRow {
                    required property var modelData
                    // One process can hold two cameras at once; the probe emits
                    // a row per (pid, device), so the device path is what tells
                    // those rows apart.
                    rowKey: "cam:" + String(modelData.device) + ":" + String(modelData.pid)
                    // `name` not `comm`: /proc/PID/comm is kernel-truncated to
                    // 15 chars and renders as "firefox-devedit". The probe
                    // already backfills name from comm, so no fallback here.
                    appName: modelData.name || "unknown"
                    pid: modelData.pid || 0
                }
            }
            GroupHeader {
                visible: pop.capture.cameraUnknown
                glyph: String.fromCodePoint(0xF071)
                title: "Camera"
                detail: "state unknown"
            }

            // --- microphone -----------------------------------------------
            RowLayout {
                visible: pop.capture.micActive
                Layout.fillWidth: true
                spacing: 6
                GroupHeader {
                    Layout.fillWidth: true
                    glyph: String.fromCodePoint(0xF130)
                    title: "Microphone"
                    // The DEFAULT source, not that stream's actual source:
                    // PwNode exposes no link information, so per-stream routing
                    // is not knowable natively. This names the device the mute
                    // button acts on, which is exactly true -- do not reword it
                    // into a claim about a given app's routing.
                    detail: pop.audio && pop.audio.source ? (pop.audio.source.description || "") : ""
                }
                Text {
                    text: pop.audio && pop.audio.sourceMuted ? "unmute" : "mute"
                    font.family: pop.theme.iconFont
                    font.pixelSize: 10
                    color: muteArea.containsMouse ? pop.theme.textPrimary : pop.theme.textSecondary
                    MouseArea {
                        id: muteArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (pop.audio) pop.audio.toggleSourceMute()
                    }
                }
            }
            Repeater {
                model: pop.capture.micActive ? pop.capture.mics : []
                AppRow {
                    required property var modelData
                    // The PipeWire node id: unique per stream, and stable across
                    // the model churn in a way the row's position is not.
                    rowKey: "mic:" + String(modelData.nodeId)
                    appName: modelData.appName
                    pid: modelData.pid || 0
                }
            }

            // --- screencast -----------------------------------------------
            GroupHeader {
                visible: pop.capture.castActive
                glyph: String.fromCodePoint(0xF06E)
                title: "Screen"
                detail: pop.capture.castActive
                    ? (pop.capture.casts[0].owner + (pop.capture.casts[0].target ? (": " + pop.capture.casts[0].target) : ""))
                    : ""
            }
            Repeater {
                model: pop.capture.castActive ? pop.capture.casts : []
                AppRow {
                    required property var modelData
                    // castsFrom collapses every active cast into one row today,
                    // so index 0 is the whole group.
                    rowKey: "cast:0"
                    appName: modelData.appName || "unknown app"
                    pid: modelData.pid || 0
                }
            }

            Text {
                visible: !pop.capture.anyActive
                Layout.fillWidth: true
                text: "Nothing is capturing"
                font.family: pop.theme.iconFont
                font.pixelSize: 10
                color: pop.theme.textSecondary
            }
        }
    }
}
