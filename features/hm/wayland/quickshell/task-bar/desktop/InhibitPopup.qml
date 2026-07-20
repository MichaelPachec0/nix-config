import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../lib" as Lib
import "../lib/inhibitlogic.js" as InhibitLogic

// Shared "stay awake" popup for the two inhibit icons. Anchored under the awake
// pill (RouterPopup idiom). Reads/writes the shared InhibitService. Two switch
// rows (label, toggle, countdown/infinity + expiry clock, +15m), each with its
// own duration preset row (left-click arms one-off, right-click sets that
// inhibitor's default; indefinite shows as an icon-width infinity), a lock that
// couples the two (individual switches disable while locked), then three context
// blocks: the idle-lock policy, power/drain, and other active inhibitors.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var barWindow
    required property var anchorItem
    required property var svc

    property bool contentHovered: cardHover.hovered

    implicitWidth: 320
    implicitHeight: col.implicitHeight + 24
    color: "transparent"
    visible: false

    anchor.window: pop.barWindow

    function reclamp() {
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.anchor.rect.x = Math.max(4, Math.min(x, pop.barWindow.width - pop.implicitWidth - 8));
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
    }
    function show() {
        if (!pop.visible) {
            pop.reclamp();
            pop.visible = true;
        }
    }
    function hide() {
        pop.visible = false;
    }
    function toggle() {
        if (pop.visible)
            pop.hide();
        else
            pop.show();
    }

    function fmtPreset(ms) {
        if (ms === 0)
            return "Until off";
        if (ms % 3600000 === 0)
            return (ms / 3600000) + "h";
        return (ms / 60000) + "m";
    }
    // Absolute expiry clock, e.g. "3:45p" (new Date is fine at QML runtime).
    function fmtClock(ms) {
        var d = new Date(ms);
        var h = d.getHours(), m = d.getMinutes();
        var ap = h >= 12 ? "p" : "a";
        h = h % 12;
        if (h === 0)
            h = 12;
        return h + ":" + (m < 10 ? "0" : "") + m + ap;
    }
    // Seconds -> human, preferring minutes so 800s reads "13m".
    function fmtDur(sec) {
        if (sec >= 3600 && sec % 3600 === 0)
            return (sec / 3600) + "h";
        if (sec >= 60)
            return Math.round(sec / 60) + "m";
        return sec + "s";
    }

    // --- idle-policy seam (Task 2 Nix file) ---
    property int lockSec: 0
    property int dpmsSec: 0
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell-idle/policy.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var p = JSON.parse(text());
                pop.lockSec = p.lockSec || 0;
                pop.dpmsSec = p.dpmsSec || 0;
            } catch (e) {
                pop.lockSec = 0;
                pop.dpmsSec = 0;
            }
        }
        Component.onCompleted: reload()
    }

    // --- power awareness ---
    readonly property var _dev: UPower.displayDevice
    readonly property bool _hasBattery: pop._dev && pop._dev.isLaptopBattery
    readonly property bool _onBattery: UPower.onBattery === true
    readonly property int _pct: pop._dev ? Math.round(pop._dev.percentage * 100) : 0
    Lib.CommandPoll {
        id: pwrPoll
        interval: 5000
        running: pop.visible && pop._hasBattery && pop._onBattery
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/battery-info.sh", "tte"]
    }

    // --- other active inhibitors (logind, structured via busctl JSON) ---
    // parse returns a display string (so CommandPoll's !== change-detection works).
    Lib.CommandPoll {
        id: inhibPoll
        interval: 3000
        running: pop.visible
        command: ["busctl", "--json=short", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "ListInhibitors"]
        parse: function (out) {
            var parts = [];
            try {
                var j = JSON.parse(out);
                var rows = (j.data && j.data[0]) ? j.data[0] : [];
                for (var i = 0; i < rows.length; i++) {
                    var what = rows[i][0], who = rows[i][1], mode = rows[i][3];
                    if (mode !== "block")
                        continue; // delay != really blocking
                    if (who === "Quickshell")
                        continue; // our own inhibitor
                    if (String(what).indexOf("sleep") < 0 && String(what).indexOf("idle") < 0)
                        continue;
                    parts.push((who || "?") + " (" + what + ")");
                }
            } catch (e) {
                parts = [];
            }
            return parts.join(", ");
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: pop.theme.radiusOuter
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border
        HoverHandler {
            id: cardHover
        }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Lib.BarText {
                text: "Stay awake"
                color: pop.theme.textPrimary
                font.family: pop.theme.textFont
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            // --- two switch rows ---
            Repeater {
                model: [
                    {
                        which: "idle",
                        label: "Keep screen awake"
                    },
                    {
                        which: "sleep",
                        label: "Prevent sleep"
                    }
                ]
                delegate: ColumnLayout {
                    id: switchRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 4

                    readonly property string which: switchRow.modelData.which
                    readonly property bool on: switchRow.which === "idle" ? pop.svc.idleOn : pop.svc.sleepOn

                    // line 1: label + toggle
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Lib.BarText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: switchRow.modelData.label
                            color: pop.theme.textPrimary
                            font.family: pop.theme.textFont
                            font.pixelSize: 12
                        }
                        Rectangle {
                            implicitWidth: 40
                            implicitHeight: 22
                            radius: 11
                            color: switchRow.on ? pop.theme.accent : pop.theme.bgItem
                            border.width: 1
                            border.color: pop.theme.border
                            Rectangle {
                                width: 16
                                height: 16
                                radius: 8
                                color: pop.theme.textPrimary
                                anchors.verticalCenter: parent.verticalCenter
                                x: switchRow.on ? parent.width - width - 3 : 3
                                Behavior on x {
                                    NumberAnimation {
                                        duration: 120
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pop.svc.toggle(switchRow.which)
                            }
                        }
                    }

                    // line 2 (only when on): countdown / infinity + expiry clock,
                    // then +15m pushed to the right. Its own line so nothing can
                    // overlap the label.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: switchRow.on
                        spacing: 8
                        Lib.BarText {
                            text: {
                                if (!switchRow.on)
                                    return "";
                                if (pop.svc.isIndefinite(switchRow.which))
                                    return pop.svc.countdownText(switchRow.which); // infinity mark
                                var exp = switchRow.which === "idle" ? pop.svc.idleExpiry : pop.svc.sleepExpiry;
                                return pop.svc.countdownText(switchRow.which) + " . til " + pop.fmtClock(exp);
                            }
                            color: pop.theme.textSecondary
                            font.family: pop.theme.iconFont
                            font.pixelSize: 11
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            visible: switchRow.on && !pop.svc.isIndefinite(switchRow.which)
                            implicitWidth: 40
                            implicitHeight: 20
                            radius: 10
                            color: ext.containsMouse ? pop.theme.bgItemHover : pop.theme.bgItem
                            Lib.BarText {
                                anchors.centerIn: parent
                                text: "+15m"
                                color: pop.theme.textPrimary
                                font.family: pop.theme.iconFont
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: ext
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pop.svc.extend(switchRow.which, 900000)
                            }
                        }
                    }

                    // Per-concern duration presets: left-click arms now (one-off);
                    // right-click sets this concern's default (used by its toggle +
                    // bar icon). The default preset is accent-highlighted. While
                    // locked, arming here couples both concerns (arm() honors lock).
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: pop.svc.presets
                            delegate: Rectangle {
                                id: chip
                                required property var modelData
                                readonly property bool isInf: chip.modelData === 0
                                readonly property bool selected: chip.modelData === pop.svc.defaultMs(switchRow.which)
                                implicitWidth: chipText.implicitWidth + (chip.isInf ? 10 : 16)
                                implicitHeight: 22
                                radius: 11
                                color: chip.selected ? pop.theme.accent
                                    : (chipHover.containsMouse ? pop.theme.bgItemHover : pop.theme.bgItem)
                                Lib.BarText {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: chip.isInf ? InhibitLogic.infinityGlyph() : pop.fmtPreset(chip.modelData)
                                    color: chip.selected ? pop.theme.textOnAccent : pop.theme.textPrimary
                                    font.family: pop.theme.iconFont
                                    font.pixelSize: chip.isInf ? 13 : 11
                                }
                                MouseArea {
                                    id: chipHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: function (mouse) {
                                        if (mouse.button === Qt.RightButton)
                                            pop.svc.setDefault(switchRow.which, chip.modelData);
                                        else
                                            pop.svc.arm(switchRow.which, chip.modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // --- lock ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Lib.BarText {
                    text: String.fromCodePoint(pop.svc.locked ? 0xF023 : 0xF09C) // fa lock / lock-open
                    color: pop.svc.locked ? pop.theme.accent : pop.theme.textSecondary
                    font.family: pop.theme.faFont
                    font.pixelSize: 12
                }
                Lib.BarText {
                    Layout.fillWidth: true
                    text: "Lock both together"
                    color: pop.theme.textPrimary
                    font.family: pop.theme.textFont
                    font.pixelSize: 12
                }
                Rectangle {
                    implicitWidth: 40
                    implicitHeight: 22
                    radius: 11
                    color: pop.svc.locked ? pop.theme.accent : pop.theme.bgItem
                    border.width: 1
                    border.color: pop.theme.border
                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        color: pop.theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                        x: pop.svc.locked ? parent.width - width - 3 : 3
                        Behavior on x {
                            NumberAnimation {
                                duration: 120
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pop.svc.setLocked(!pop.svc.locked)
                    }
                }
            }

            // --- divider ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: pop.theme.border
            }

            // --- context: idle-lock policy ---
            Lib.BarText {
                visible: pop.lockSec > 0
                Layout.fillWidth: true
                text: "When off: locks " + pop.fmtDur(pop.lockSec) + " . screen off " + pop.fmtDur(pop.dpmsSec)
                color: pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            // --- context: power / drain ---
            Lib.BarText {
                visible: pop._hasBattery
                Layout.fillWidth: true
                text: {
                    if (!pop._onBattery)
                        return "On AC . " + pop._pct + "%";
                    var t = (pwrPoll.value && String(pwrPoll.value).length > 0) ? " . ~" + pwrPoll.value + " to empty" : "";
                    return "On battery . " + pop._pct + "%" + t;
                }
                color: pop._onBattery ? pop.theme.accentOrange : pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            // --- context: other active inhibitors ---
            Lib.BarText {
                Layout.fillWidth: true
                text: (inhibPoll.value && String(inhibPoll.value).length > 0) ? "Also blocking: " + inhibPoll.value : "Nothing else is blocking sleep/idle"
                color: pop.theme.textSecondary
                font.family: pop.theme.textFont
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }
}
