import QtQuick
import QtQuick.Layouts
import Quickshell

// Hub Header card (Phase 2d): an initials profile chip + name, CPU/RAM chips, a
// screenshot button (region grab via grim + slurp, matching the repo helper),
// and a power button that expands an inline PowerMenuGrid (step 4) whose actions
// are mapped to shell commands by runPowerAction. The surface-dots theme-toggle
// button is dropped for v1 (Gruvbox-dark only; the light/Everforest switcher is
// post-v1).
Item {
    id: root

    required property QtObject theme
    property string profileName: "Michael"
    property string initial: "M"
    property bool expanded: false

    // Shared CPU/RAM stats (lib/SysStats), provided by HubWindow.
    property QtObject stats: null

    // Emitted before a screenshot so the hub closes first.
    signal closeRequested

    implicitHeight: 52 + root.powerContainerHeight
    // Animated height of the inline power menu: 0 collapsed, grid height expanded.
    property real powerContainerHeight: root.expanded ? (powerGrid.implicitHeight + 8) : 0
    Behavior on powerContainerHeight {
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutCubic
        }
    }

    function togglePower() {
        root.expanded = !root.expanded;
    }

    // Map a power action to a shell command and fire it, then close the hub.
    function runPowerAction(action) {
        var cmd = "";
        switch (action) {
        case "lock":
            cmd = "loginctl lock-session";
            break;
        case "suspend":
            cmd = "systemctl suspend";
            break;
        case "logout":
            // UWSM-managed: graceful `uwsm stop`, else exit Hyprland directly.
            cmd = "if command -v uwsm >/dev/null 2>&1; then uwsm stop || hyprctl dispatch exit; else hyprctl dispatch exit; fi";
            break;
        case "hibernate":
            cmd = "systemctl hibernate";
            break;
        case "reboot":
            cmd = "systemctl reboot";
            break;
        case "shutdown":
            cmd = "systemctl poweroff";
            break;
        }
        if (cmd !== "")
            Quickshell.execDetached(["bash", "-c", cmd]);
        root.closeRequested();
    }

    // Region screenshot, matching common.nix's grim+slurp helper. Fired after a
    // short delay so the (closing) hub overlay is gone before slurp's selection.
    Timer {
        id: snapTimer
        interval: 320
        onTriggered: Quickshell.execDetached(["bash", "-c", "grim -t png -g \"$(slurp)\" ~/Pictures/scrn-$(date +%Y-%m-%dT%H:%M:%S%:z).png"])
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            spacing: 12

            // Profile: initials chip
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 34
                height: 34
                radius: 10
                color: root.theme.accent
                Text {
                    anchors.centerIn: parent
                    text: root.initial
                    color: root.theme.textOnAccent
                    font.family: root.theme.textFont
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.profileName
                color: root.theme.textPrimary
                font.family: root.theme.textFont
                font.pixelSize: 18
                font.weight: Font.Bold
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            // CPU / RAM chips: Font Awesome glyph (faFont, no digits) + value
            // (textFont). microchip = U+F2DB, memory = U+F538.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 19
                implicitWidth: cpuRow.implicitWidth + 14
                radius: 9
                color: root.theme.bgItem
                RowLayout {
                    id: cpuRow
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        text: String.fromCharCode(0xF2DB)
                        color: root.theme.textSecondary
                        font.family: root.theme.faFont
                        font.pixelSize: 10
                    }
                    Text {
                        text: Math.round(root.stats ? root.stats.cpuPct : 0) + "%"
                        color: root.theme.textSecondary
                        font.family: root.theme.textFont
                        font.pixelSize: 11
                    }
                }
            }
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 19
                implicitWidth: ramRow.implicitWidth + 14
                radius: 9
                color: root.theme.bgItem
                RowLayout {
                    id: ramRow
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        text: String.fromCharCode(0xF538)
                        color: root.theme.textSecondary
                        font.family: root.theme.faFont
                        font.pixelSize: 10
                    }
                    Text {
                        text: Math.round(root.stats ? root.stats.ramPct : 0) + "%"
                        color: root.theme.textSecondary
                        font.family: root.theme.textFont
                        font.pixelSize: 11
                    }
                }
            }

            // Screenshot
            Rectangle {
                id: snapBtn
                Layout.alignment: Qt.AlignVCenter
                width: 30
                height: 30
                radius: 12
                color: snapHover.hovered ? root.theme.subtleFillHover : root.theme.subtleFill
                border.width: 1
                border.color: root.theme.outline
                scale: snapTap.pressed ? 0.95 : 1.0
                Behavior on scale {
                    NumberAnimation {
                        duration: 90
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: "\uEB4C"
                    font.family: root.theme.iconFont
                    font.pixelSize: 16
                    color: root.theme.textPrimary
                }
                HoverHandler {
                    id: snapHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    id: snapTap
                    onTapped: {
                        root.closeRequested();
                        snapTimer.restart();
                    }
                }
            }

            // Power (toggles the inline power menu)
            Rectangle {
                id: pwrBtn
                Layout.alignment: Qt.AlignVCenter
                width: 30
                height: 30
                radius: 12
                color: (pwrHover.hovered || root.expanded) ? root.theme.accentRed : root.theme.subtleFill
                border.width: 1
                border.color: root.expanded ? root.theme.accentRed : root.theme.outline
                scale: pwrTap.pressed ? 0.95 : 1.0
                Behavior on scale {
                    NumberAnimation {
                        duration: 90
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: root.expanded ? "\uF00D" : "\uF011"
                    font.family: root.theme.iconFont
                    font.pixelSize: 13
                    color: (pwrHover.hovered || root.expanded) ? root.theme.textOnAccent : root.theme.accentRed
                }
                HoverHandler {
                    id: pwrHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    id: pwrTap
                    onTapped: root.togglePower()
                }
            }
        }

        // Inline power-menu container -- clips the grid as it slides open/closed.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.powerContainerHeight
            clip: true
            PowerMenuGrid {
                id: powerGrid
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 8
                theme: root.theme
                active: root.expanded
                onActionRequested: action => root.runPowerAction(action)
            }
        }
    }
}
