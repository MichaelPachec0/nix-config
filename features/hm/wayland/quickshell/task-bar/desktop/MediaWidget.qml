import QtQuick
import "../lib" as Lib
import QtQuick.Layouts
import Quickshell.Services.Mpris

// Bar MPRIS widget: a play/pause toggle + the current track ("Title - Artist")
// as marquee text that ping-pong scrolls when it overflows a capped width. Only
// shown while a player is playing or paused; collapses out of the bar otherwise.
// Shares the MediaCard's player-pick logic (playing > paused > first).
Item {
    id: root

    required property QtObject theme
    required property var barWindow // the bar PanelWindow, for popup anchoring
    // Named `capture` while shell.qml's id is `captureSvc`: an own-property
    // shadows an enclosing-component id across the Variants delegate, so
    // matching names would silently bind this to its own null property.
    required property var capture
    required property var audio
    property int maxTextWidth: 80
    // Drop a not-playing picked player for an active one after this long.
    property int autoSwitchMs: 10000

    // Drop the playerctld proxy (a duplicate that mirrors the active player).
    readonly property var players: (Mpris.players.values || []).filter(function (p) {
        return p && (p.dbusName || "").indexOf("playerctld") < 0;
    })
    // autoPlayer is the auto-pick (now-playing); it seeds the popup's default.
    // The EFFECTIVE player the bar shows is the popup's selection, so a chip
    // choice in the popup is reflected here too (and falls back to the auto-pick
    // when the user hasn't chosen one).
    //
    // Reactive binding: QML re-evaluates it whenever the players list changes or
    // the currently-picked player's playback state changes, so no polling is
    // needed. _repick is bumped by the slow presence-gated backstop below purely
    // as a safety net if an MPRIS NOTIFY is ever dropped.
    property int _repick: 0
    readonly property MprisPlayer autoPlayer: {
        root._repick; // dependency: lets the backstop force a periodic re-eval
        var ps = root.players || [];
        for (var i = 0; i < ps.length; i++)
            if (ps[i] && ps[i].isPlaying)
                return ps[i];
        for (var j = 0; j < ps.length; j++)
            if (ps[j] && ps[j].playbackState === MprisPlaybackState.Paused)
                return ps[j];
        return ps.length ? ps[0] : null;
    }
    readonly property MprisPlayer player: popup.player
    Timer {
        interval: 5000
        repeat: true
        running: (root.players || []).length > 0
        onTriggered: root._repick++
    }

    readonly property bool hasPlayer: root.player !== null
    readonly property int pbState: root.player ? root.player.playbackState : MprisPlaybackState.Stopped
    readonly property bool isPlaying: root.pbState === MprisPlaybackState.Playing
    readonly property bool active: root.hasPlayer && root.pbState !== MprisPlaybackState.Stopped

    readonly property string title: root.player ? (root.player.trackTitle || "Unknown") : ""
    readonly property string artist: root.player ? (root.player.trackArtist || "") : ""
    readonly property string label: root.artist ? (root.title + "  -  " + root.artist) : root.title

    // The pill must appear for a hot device even with NO media playing --
    // `visible: root.active` alone collapsed the whole widget, so the capture
    // glyphs could never show without music.
    readonly property bool captureActive: root.capture ? root.capture.anyActive : false
    visible: root.active || root.captureActive
    implicitWidth: (root.active || root.captureActive) ? row.implicitWidth : 0
    implicitHeight: 24

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 6

        // Play / pause toggle. Hidden with no MPRIS player: the widget now also
        // renders in capture-only mode, where a play glyph would be dead.
        Lib.BarText {
            visible: root.hasPlayer
            Layout.alignment: Qt.AlignVCenter
            text: String.fromCodePoint(root.isPlaying ? 0xF04C : 0xF04B)
            font.family: root.theme.iconFont
            font.pixelSize: 13
            color: playHover.hovered ? root.theme.textPrimary : root.theme.textSecondary
            HoverHandler {
                id: playHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: if (root.player && root.player.canTogglePlaying)
                    root.player.togglePlaying()
            }
        }

        // Marquee: clip the label to a capped width and ping-pong scroll it when
        // it overflows. A short pause at each end keeps it readable.
        Item {
            id: marquee
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Math.min(label.implicitWidth, root.maxTextWidth)
            Layout.preferredHeight: 24
            clip: true

            readonly property real scrollDist: Math.max(0, label.implicitWidth - marquee.width)
            readonly property bool overflow: marquee.scrollDist > 0
            // ms per pixel: higher = slower. ~11 px/s.
            readonly property int scrollDur: Math.max(2000, marquee.scrollDist * 90)

            Lib.BarText {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                font.family: root.theme.iconFont
                font.pixelSize: 11
                color: root.theme.textPrimary
                onTextChanged: x = 0
            }

            SequentialAnimation {
                running: marquee.overflow && root.isPlaying
                loops: Animation.Infinite
                onRunningChanged: if (!running)
                    label.x = 0
                PauseAnimation {
                    duration: 1400
                }
                NumberAnimation {
                    target: label
                    property: "x"
                    from: 0
                    to: -marquee.scrollDist
                    duration: marquee.scrollDur
                    easing.type: Easing.InOutQuad
                }
                PauseAnimation {
                    duration: 1400
                }
                NumberAnimation {
                    target: label
                    property: "x"
                    from: -marquee.scrollDist
                    to: 0
                    duration: marquee.scrollDur
                    easing.type: Easing.InOutQuad
                }
            }
        }

        // Capture glyphs. Rendered only while their signal is active, so the
        // bar stays quiet when nothing is capturing. The camera glyph is the
        // one exception: when the scan could not answer it renders in the
        // warning tint rather than hiding, because hiding it would both make
        // this popup unreachable and silently assert the camera is idle.
        //
        // Wrapped in a plain Item (not Row) so the click-target MouseArea can
        // anchors.fill it: Row is a positioner and refuses fill/horizontal
        // anchors on its children ("Row will not function" at runtime),
        // which would leave the MouseArea zero-sized and the glyphs
        // unclickable.
        Item {
            id: glyphs
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: glyphRow.implicitWidth
            implicitHeight: glyphRow.implicitHeight
            visible: root.captureActive

            Row {
                id: glyphRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Lib.BarText {
                    visible: root.capture && (root.capture.cameraActive || root.capture.cameraUnknown)
                    text: String.fromCodePoint(0xF030)
                    font.family: root.theme.iconFont
                    font.pixelSize: 12
                    color: (root.capture && root.capture.cameraUnknown) ? root.theme.accentYellow : root.theme.accentRed
                }
                Lib.BarText {
                    visible: root.capture && root.capture.micActive
                    text: String.fromCodePoint(0xF130)
                    font.family: root.theme.iconFont
                    font.pixelSize: 12
                    color: root.theme.accentRed
                }
                Lib.BarText {
                    visible: root.capture && root.capture.castActive
                    text: String.fromCodePoint(0xF06E)
                    font.family: root.theme.iconFont
                    font.pixelSize: 12
                    color: root.theme.accentRed
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton
                onClicked: devicePopup.toggle()
            }
        }
    }

    // Hover anywhere on the widget reveals the full-player popup; it stays open
    // while the cursor is on the widget OR the popup (a short debounce bridges
    // the gap between them), so the popup's seek/controls are reachable.
    HoverHandler {
        id: widgetHover
    }
    readonly property bool over: widgetHover.hovered || popup.contentHovered
    // Gated on hasPlayer: in capture-only mode there is no player, and the glyph
    // click target sits inside the widget, so hovering to reach it would open a
    // blank player card that then overlaps the DevicePopup.
    onOverChanged: {
        if (root.over && root.hasPlayer) {
            hideTimer.stop();
            popup.showPopup();
        } else {
            hideTimer.restart();
        }
    }
    Timer {
        id: hideTimer
        interval: 250
        onTriggered: popup.hide()
    }

    MediaPopup {
        id: popup
        theme: root.theme
        barWindow: root.barWindow
        anchorItem: root
        defaultPlayer: root.autoPlayer
        autoSwitchMs: root.autoSwitchMs
    }

    DevicePopup {
        id: devicePopup
        theme: root.theme
        barWindow: root.barWindow
        anchorItem: root
        capture: root.capture
        audio: root.audio
    }

    // Close on lock. A grabFocus bar popup open when the session locks has
    // crashed Hyprland 0.56 (see the hypr-popup-lock-crash notes); the
    // compositor-side guard is a local patch, so do not rely on it alone.
    Connections {
        target: root.capture
        function onLockedChanged() {
            if (root.capture.locked)
                devicePopup.visible = false;
        }
    }
}
