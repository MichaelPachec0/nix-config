import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

// Hub Media card (Phase 2d, step 5): MPRIS now-playing -- album art, title,
// artist, a linear progress bar with elapsed/total time, and prev/play-pause/
// next. Collapses to zero height (and drops out of the layout) when no player is
// playing or paused. Simplified from surface-dots: no album-art colour
// extraction or wavy progress (Gruvbox-themed; those are post-v1). Quickshell's
// MprisPlayer reports position/length already in seconds, so no unit guessing.
Rectangle {
    id: root

    required property QtObject theme

    // True while the hub overlay is actually shown (fed from HubWindow, like the
    // sibling cards). Gates the poll timers -- root.visible can't, since it stays
    // true whenever a player exists, so the timers would run per monitor with the
    // hub closed.
    property bool active: true

    signal closeRequested

    // --- player selection: prefer a playing one, else paused, else first ---
    // Drop the playerctld proxy (a duplicate that mirrors the active player).
    readonly property var players: (Mpris.players.values || []).filter(function (p) {
        return p && (p.dbusName || "").indexOf("playerctld") < 0;
    })
    // Auto-pick as a reactive binding: QML re-evaluates it whenever the players
    // list changes or the currently-picked player's playback state changes, so
    // no polling is needed. Dependency tracking follows the priority order -- it
    // subscribes to each player's isPlaying only until the first match, and
    // re-picks when that player later stops. _repick is bumped by the slow
    // presence-gated backstop below purely as a safety net if an MPRIS NOTIFY is
    // ever dropped.
    property int _repick: 0
    readonly property MprisPlayer player: {
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
    Timer {
        interval: 5000
        repeat: true
        running: root.active && (root.players || []).length > 0
        onTriggered: root._repick++
    }

    readonly property bool hasPlayer: root.player !== null
    readonly property int pbState: root.player ? root.player.playbackState : MprisPlaybackState.Stopped
    readonly property bool isPlaying: root.pbState === MprisPlaybackState.Playing
    // Visible while a player is playing or paused; collapses when stopped/gone.
    readonly property bool playerActive: root.hasPlayer && root.pbState !== MprisPlaybackState.Stopped

    // --- track + time ---
    readonly property string title: root.player ? (root.player.trackTitle || "Unknown Title") : ""
    readonly property string artist: root.player ? (root.player.trackArtist || "Unknown Artist") : ""
    readonly property string artUrl: root.player ? (root.player.trackArtUrl || "") : ""
    readonly property real lenSec: root.player ? (root.player.length || 0) : 0
    property real posSec: 0
    readonly property real progress: root.lenSec > 0 ? Math.max(0, Math.min(1, root.posSec / root.lenSec)) : 0

    onPlayerChanged: root.posSec = root.player ? root.player.position : 0
    // Poll position while open (reading it always returns the current value;
    // Quickshell only updates it reactively for nonlinear jumps).
    Timer {
        interval: 1000
        repeat: true
        running: root.active && root.hasPlayer
        triggeredOnStart: true
        onTriggered: root.posSec = root.player ? root.player.position : 0
    }

    function fmt(s) {
        if (isNaN(s) || s < 0)
            return "0:00";
        var m = Math.floor(s / 60);
        var ss = Math.floor(s % 60);
        return m + ":" + (ss < 10 ? "0" : "") + ss;
    }

    // --- collapse / appearance ---
    readonly property int baseHeight: 112
    implicitHeight: root.playerActive ? root.baseHeight : 0
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }
    visible: implicitHeight > 1 // drops out of the hub layout once fully collapsed
    opacity: root.playerActive ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: 170
        }
    }
    clip: true

    radius: root.theme.radiusOuter
    color: root.theme.bgCard
    border.width: 1
    border.color: root.theme.border

    // Round transport button: a glyph with hover/press feedback; `primary` is the
    // larger filled play/pause; dims + ignores input when its action is disabled.
    component CtlButton: Rectangle {
        id: ctl
        property int glyph: 0
        property int glyphSize: 15
        property bool primary: false
        property bool enabledAction: true
        property bool active: false // accent-tint the glyph (repeat/shuffle engaged)
        signal activated

        width: primary ? 42 : 32
        height: primary ? 42 : 32
        radius: width / 2
        color: primary ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, ctlHover.hovered ? 0.28 : 0.18) : (ctlHover.hovered ? root.theme.bgItemHover : "transparent")
        opacity: ctl.enabledAction ? 1 : 0.35
        Behavior on color {
            ColorAnimation {
                duration: 130
            }
        }
        scale: ctlTap.pressed ? 0.9 : 1
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(ctl.glyph)
            color: ctl.active ? root.theme.accent : (ctl.primary ? root.theme.textPrimary : root.theme.textSecondary)
            font.family: root.theme.iconFont
            font.pixelSize: ctl.glyphSize
        }
        HoverHandler {
            id: ctlHover
            enabled: ctl.enabledAction
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: ctlTap
            enabled: ctl.enabledAction
            onTapped: ctl.activated()
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 12

        // Album art (square) with a music-note fallback.
        Rectangle {
            Layout.preferredWidth: 88
            Layout.preferredHeight: 88
            Layout.alignment: Qt.AlignVCenter
            radius: 8
            color: root.theme.bgItem
            clip: true
            Text {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: String.fromCodePoint(0xF001) // music note
                color: root.theme.textSecondary
                font.family: root.theme.iconFont
                font.pixelSize: 30
            }
            Image {
                id: art
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 176
                sourceSize.height: 176
            }
        }

        // Title / artist / progress + times.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 3

            Item {
                Layout.fillHeight: true
            }

            Text {
                Layout.fillWidth: true
                text: root.title
                color: root.theme.textPrimary
                font.family: root.theme.textFont
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: root.artist
                color: root.theme.textSecondary
                font.family: root.theme.textFont
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            // Progress bar
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 4
                radius: 2
                color: root.theme.bgItem
                Rectangle {
                    width: parent.width * root.progress
                    height: parent.height
                    radius: 2
                    color: root.theme.accent
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.fmt(root.posSec)
                    color: root.theme.textSecondary
                    font.family: root.theme.textFont
                    font.pixelSize: 10
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: root.lenSec > 0.5 ? root.fmt(root.lenSec) : "--:--"
                    color: root.theme.textSecondary
                    font.family: root.theme.textFont
                    font.pixelSize: 10
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }

        // Transport controls: shuffle / repeat stacked ABOVE prev / play-pause /
        // next, so the cluster stays as narrow as the primary trio (114px) and the
        // title/artist column reclaims the width the flat 5-button row was eating.
        // Every button keeps its size. The secondary row is hidden outright when
        // the player supports neither toggle, so simple players lose no height.
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                visible: root.player ? (root.player.shuffleSupported || root.player.loopSupported) : false

                CtlButton {
                    glyph: 0xF049D // shuffle
                    glyphSize: 12
                    visible: root.player ? root.player.shuffleSupported : false
                    active: root.player ? root.player.shuffle : false
                    onActivated: if (root.player)
                        root.player.shuffle = !root.player.shuffle
                }
                CtlButton {
                    // repeat: off -> all (Playlist) -> one (Track) -> off; repeat-once
                    // glyph marks Track mode, else the plain repeat glyph.
                    glyph: (root.player && root.player.loopState === MprisLoopState.Track) ? 0xF0458 : 0xF0456
                    glyphSize: 12
                    visible: root.player ? root.player.loopSupported : false
                    active: root.player ? root.player.loopState !== MprisLoopState.None : false
                    onActivated: {
                        if (!root.player)
                            return;
                        var s = root.player.loopState;
                        root.player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist : (s === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None);
                    }
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                CtlButton {
                    glyph: 0xF048 // step-backward
                    enabledAction: root.player ? root.player.canGoPrevious : false
                    onActivated: if (root.player)
                        root.player.previous()
                }
                CtlButton {
                    glyph: root.isPlaying ? 0xF04C : 0xF04B // pause / play
                    glyphSize: 18
                    primary: true
                    enabledAction: root.player ? root.player.canTogglePlaying : false
                    onActivated: if (root.player)
                        root.player.togglePlaying()
                }
                CtlButton {
                    glyph: 0xF051 // step-forward
                    enabledAction: root.player ? root.player.canGoNext : false
                    onActivated: if (root.player)
                        root.player.next()
                }
            }
        }
    }
}
