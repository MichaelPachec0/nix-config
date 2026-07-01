import QtQuick
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
    property MprisPlayer autoPlayer: null
    readonly property MprisPlayer player: popup.player

    function pickPlayer() {
        var ps = root.players || [];
        for (var i = 0; i < ps.length; i++)
            if (ps[i] && ps[i].isPlaying) {
                root.autoPlayer = ps[i];
                return;
            }
        for (var j = 0; j < ps.length; j++)
            if (ps[j] && ps[j].playbackState === MprisPlaybackState.Paused) {
                root.autoPlayer = ps[j];
                return;
            }
        root.autoPlayer = ps.length ? ps[0] : null;
    }
    Timer {
        interval: 1500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.pickPlayer()
    }

    readonly property bool hasPlayer: root.player !== null
    readonly property int pbState: root.player ? root.player.playbackState : MprisPlaybackState.Stopped
    readonly property bool isPlaying: root.pbState === MprisPlaybackState.Playing
    readonly property bool active: root.hasPlayer && root.pbState !== MprisPlaybackState.Stopped

    readonly property string title: root.player ? (root.player.trackTitle || "Unknown") : ""
    readonly property string artist: root.player ? (root.player.trackArtist || "") : ""
    readonly property string label: root.artist ? (root.title + "  -  " + root.artist) : root.title

    visible: root.active
    implicitWidth: root.active ? row.implicitWidth : 0
    implicitHeight: 24

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 6

        // Play / pause toggle.
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: String.fromCodePoint(root.isPlaying ? 0xF04C : 0xF04B)
            font.family: root.theme.iconFont
            font.pixelSize: 12
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

            Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                font.family: root.theme.textFont
                font.pixelSize: 11
                color: root.theme.textSecondary
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
    }

    // Hover anywhere on the widget reveals the full-player popup; it stays open
    // while the cursor is on the widget OR the popup (a short debounce bridges
    // the gap between them), so the popup's seek/controls are reachable.
    HoverHandler {
        id: widgetHover
    }
    readonly property bool over: widgetHover.hovered || popup.contentHovered
    onOverChanged: {
        if (root.over) {
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
}
