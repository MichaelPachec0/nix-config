import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// The Hub overlay shell (Phase 2d, step 1). A per-monitor fullscreen, normally
// hidden, transparent overlay layer. When toggled it dims the screen and slides
// a Gruvbox-themed panel down from the top-right, just below the taskbar; click
// the dim, press Escape, or re-toggle to close. Toggled by shell.qml's
// "hubToggle" GlobalShortcut.
PanelWindow {
    id: win

    required property QtObject theme
    property QtObject stats: null

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    visible: false
    // Cover the whole output (ignore the dock's reserved strip) so the dim is
    // full-screen rather than starting below the bar.
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-hub"
    // Grab the keyboard while open so Escape closes it; released when hidden.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Panel geometry (fixed for now; re-tune for thanatos later). barHeight
    // matches the dock's implicitHeight so the panel sits just below the taskbar
    // (the overlay covers the full output, so its top is the screen top).
    readonly property int panelW: 420
    readonly property int edgeGap: 12
    readonly property int barHeight: 40

    function open() {
        if (!win.visible)
            win.visible = true; // onVisibleChanged kicks off the enter animation
    }
    function close() {
        if (win.visible && !exitAnim.running)
            exitAnim.start(); // hides the window onFinished
    }
    function toggle() {
        if (win.visible)
            win.close();
        else
            win.open();
    }

    onVisibleChanged: if (win.visible) {
        panelTranslate.y = -panel.height; // start above; slide down into view
        panel.opacity = 0;
        dim.opacity = 0;
        enterAnim.start();
        root.forceActiveFocus();
    }

    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.close()

        // Dimmed backdrop; a click anywhere outside the panel closes the hub.
        Rectangle {
            id: dim
            anchors.fill: parent
            color: "#000000"
            opacity: 0
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: win.close()
            }
        }

        Rectangle {
            id: panel
            width: win.panelW
            height: content.implicitHeight + 24
            radius: 14
            color: win.theme.bgMain
            border.width: 1
            border.color: win.theme.border
            anchors {
                right: parent.right
                top: parent.top
                rightMargin: win.edgeGap
                topMargin: win.barHeight + win.edgeGap
            }
            transform: Translate {
                id: panelTranslate
            }

            // Clicks inside the panel must not fall through to the dim/close.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: mouse => mouse.accepted = true
            }

            // Cards stack here, top-down (step 2+).
            ColumnLayout {
                id: content
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 12
                }
                spacing: 10

                Header {
                    Layout.fillWidth: true
                    theme: win.theme
                    stats: win.stats
                    onCloseRequested: win.close()
                }

                CalendarWeatherCard {
                    Layout.fillWidth: true
                    theme: win.theme
                    active: win.visible
                }

                MediaCard {
                    Layout.fillWidth: true
                    theme: win.theme
                    onCloseRequested: win.close()
                }

                ButtonsSlidersCard {
                    Layout.fillWidth: true
                    theme: win.theme
                    active: win.visible
                    onCloseRequested: win.close()
                }

                BatteryCard {
                    Layout.fillWidth: true
                    theme: win.theme
                }
            }

            ParallelAnimation {
                id: enterAnim
                NumberAnimation {
                    target: panelTranslate
                    property: "y"
                    from: -panel.height
                    to: 0
                    duration: 280
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: panel
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 220
                }
                NumberAnimation {
                    target: dim
                    property: "opacity"
                    from: 0
                    to: 0.35
                    duration: 220
                }
            }
            ParallelAnimation {
                id: exitAnim
                onFinished: win.visible = false
                NumberAnimation {
                    target: panelTranslate
                    property: "y"
                    from: 0
                    to: -panel.height
                    duration: 180
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: panel
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: 140
                }
                NumberAnimation {
                    target: dim
                    property: "opacity"
                    from: 0.35
                    to: 0
                    duration: 140
                }
            }
        }
    }
}
