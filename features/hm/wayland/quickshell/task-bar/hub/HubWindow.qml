import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// The Hub overlay shell (Phase 2d, step 1; notifications split out in 2f). A
// per-monitor fullscreen, normally hidden, transparent overlay. When toggled it
// dims the screen and slides a stack of Gruvbox panels down from the top-right,
// just below the taskbar. Two surfaces share this one overlay via `mode`:
//   - "full"  (SUPER+Alt_R): the hub panel + the notifications panel below it.
//   - "notif" (SUPER+N):     only the notifications panel.
// Click the dim, press Escape, or re-toggle to close. Driven by shell.qml's
// "hubToggle" / "notifToggle" GlobalShortcuts.
PanelWindow {
    id: win

    required property QtObject theme
    property QtObject stats: null
    property QtObject weatherState: null
    property QtObject notif: null

    // "full" = hub + notifications; "notif" = notifications only.
    property string mode: "full"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    visible: false
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-hub"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property int panelW: 420
    readonly property int edgeGap: 12
    readonly property int barHeight: 40
    // Right margin for card content INSIDE each panel -- wider than the left so
    // the scrollbar (which sits over the panel's right edge) clears the cards.
    readonly property int scrollLane: 18

    function open() {
        if (!win.visible)
            win.visible = true; // onVisibleChanged kicks off the enter animation
    }
    function close() {
        if (win.visible && !exitAnim.running)
            exitAnim.start(); // hides the window onFinished
    }
    // SUPER+Alt_R: hub + notifications. Re-press closes; from notif-only it
    // switches to full without re-animating.
    function hubToggle() {
        if (win.visible && win.mode === "full")
            win.close();
        else {
            win.mode = "full";
            win.open();
        }
    }
    // SUPER+N: notifications only.
    function notifToggle() {
        if (win.visible && win.mode === "notif")
            win.close();
        else {
            win.mode = "notif";
            win.open();
        }
    }

    onVisibleChanged: if (win.visible) {
        scroller.contentY = 0; // always open scrolled to the top
        stackTranslate.y = -scroller.height; // start above; slide down into view
        scroller.opacity = 0;
        dim.opacity = 0;
        enterAnim.start();
        root.forceActiveFocus();
    }
    // Switching mode while open resets the scroll position.
    onModeChanged: if (win.visible)
        scroller.contentY = 0

    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.close()

        // Dimmed backdrop; a click anywhere outside the panels closes the hub.
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

        // Scrollable container for the panel stack. Bounded to the space below
        // the bar; scrolls (only) when the content is taller than that -- e.g. a
        // long notifications list. interactive: true also keeps clicks inside the
        // panels from falling through to the dim. The notification ListView is
        // non-interactive, so this is the single scroller (no nested flicking).
        Flickable {
            id: scroller
            anchors {
                right: parent.right
                top: parent.top
                rightMargin: win.edgeGap
                topMargin: win.barHeight + win.edgeGap
            }
            width: win.panelW
            height: Math.min(stack.implicitHeight, root.height - win.barHeight - win.edgeGap * 2)
            contentWidth: width
            contentHeight: stack.implicitHeight
            clip: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            transform: Translate {
                id: stackTranslate
            }

            // Thin themed scrollbar. Shown only when the content overflows; when
            // everything fits it's fully hidden, but the lane stays reserved (the
            // content's right margin is constant) so nothing shifts.
            ScrollBar.vertical: ScrollBar {
                id: vbar
                policy: scroller.contentHeight > scroller.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                width: 15
                rightPadding: 7 // sit the thumb just inside the panel's right edge
                topPadding: 16 // keep the thumb inside the panel's rounded ends
                bottomPadding: 16
                contentItem: Rectangle {
                    implicitWidth: 8
                    radius: 4
                    color: win.theme.textSecondary
                    opacity: vbar.pressed ? 0.8 : (vbar.active ? 0.65 : 0.45)
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                }
            }

            ColumnLayout {
                id: stack
                width: scroller.width // panels fill the scroller; bar overlaps them
                spacing: 10

                // --- Hub panel (Header / Calendar+Weather / Media / Quick / Battery)
                Rectangle {
                    id: hubPanel
                    visible: win.mode === "full"
                    Layout.fillWidth: true
                    implicitHeight: hubContent.implicitHeight + 24
                    radius: 14
                    color: win.theme.bgMain
                    border.width: 1
                    border.color: win.theme.border

                    ColumnLayout {
                        id: hubContent
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            leftMargin: 12
                            topMargin: 12
                            rightMargin: win.scrollLane
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
                            active: win.visible && win.mode === "full"
                            weatherState: win.weatherState
                        }
                        MediaCard {
                            Layout.fillWidth: true
                            theme: win.theme
                            onCloseRequested: win.close()
                        }
                        ButtonsSlidersCard {
                            Layout.fillWidth: true
                            theme: win.theme
                            active: win.visible && win.mode === "full"
                            notif: win.notif
                            onCloseRequested: win.close()
                        }
                        BatteryCard {
                            Layout.fillWidth: true
                            theme: win.theme
                        }
                    }
                }

                // --- Notifications panel (always shown while open) -------------
                Rectangle {
                    id: notifPanel
                    Layout.fillWidth: true
                    implicitHeight: notifContent.implicitHeight + 24
                    radius: 14
                    color: win.theme.bgMain
                    border.width: 1
                    border.color: win.theme.border

                    ColumnLayout {
                        id: notifContent
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            leftMargin: 12
                            topMargin: 12
                            rightMargin: win.scrollLane
                        }
                        spacing: 10

                        NotificationsCard {
                            Layout.fillWidth: true
                            theme: win.theme
                            notif: win.notif
                        }
                    }
                }
            }
        }

        ParallelAnimation {
            id: enterAnim
            NumberAnimation {
                target: stackTranslate
                property: "y"
                from: -scroller.height
                to: 0
                duration: 280
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: scroller
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
                target: stackTranslate
                property: "y"
                from: 0
                to: -scroller.height
                duration: 180
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: scroller
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
