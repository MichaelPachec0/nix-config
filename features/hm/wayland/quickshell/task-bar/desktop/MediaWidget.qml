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

    visible: root.active
    implicitWidth: root.active ? row.implicitWidth : 0
    implicitHeight: 24

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 6

        // Play / pause toggle.
        Lib.BarText {
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
            readonly property int endPauseMs: 1400

            Lib.BarText {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                font.family: root.theme.iconFont
                font.pixelSize: 11
                color: root.theme.textPrimary
                onTextChanged: marquee.resetScroll()
            }

            // Marquee stepping, deliberately NOT a NumberAnimation.
            //
            // A QtQuick animation drives the scene-graph animation clock, so the
            // render thread wakes on every vblank for the animation's whole
            // duration. This marquee runs while ANY media plays -- with a long
            // title, scrollDur is ~12.6s a sweep against 1400ms end pauses, a
            // ~90% duty cycle -- and the bar is instantiated per screen
            // (Variants over Quickshell.screens in shell.qml), so the cost is
            // paid once per monitor. On top of that the bar layer is blurred
            // (the "frost the bar" layer_rule in hyprland.nix), so every frame
            // also makes the compositor re-run its blur passes over the bar.
            // Measured: quickshell at 26.5% CPU with a track playing vs 2.8%
            // paused, on a 120Hz output.
            //
            // Stepping x from a timer instead caps that at stepMs regardless of
            // refresh rate. The InOutQuad easing is applied by hand so the
            // motion still matches the sibling marquees. Elapsed time is
            // accumulated from the fixed interval rather than read off a clock:
            // a late tick then slows the scroll fractionally instead of jumping
            // the label, which is the nicer failure mode for a decoration.
            readonly property int stepMs: 66 // ~15fps
            // 0 = pause at start, 1 = scroll out, 2 = pause at end, 3 = scroll back
            property int phase: 0
            property int elapsed: 0

            function resetScroll() {
                phase = 0;
                elapsed = 0;
                label.x = 0;
            }

            // InOutQuad, matching easing.type: Easing.InOutQuad.
            function ease(t) {
                return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
            }

            Timer {
                interval: marquee.stepMs
                repeat: true
                // surfaceVisible: don't scroll into a bar that a fullscreen
                // window is covering -- the frame callbacks keep coming, so the
                // stepping would render at full rate for nothing.
                //
                // Hover-gated by default (Lib.MediaState.marqueeAlways = false),
                // because continuous scrolling is the single largest idle
                // battery item on this machine -- see the marquee chip in
                // MediaPopup.qml for the measurement. Hovering still scrolls a
                // PAUSED title on purpose: that is a deliberate action, not an
                // idle background cost.
                running: marquee.overflow && root.barWindow.surfaceVisible && (Lib.MediaState.marqueeAlways ? root.isPlaying : widgetHover.hovered)
                onRunningChanged: if (!running)
                    marquee.resetScroll()
                onTriggered: {
                    marquee.elapsed += marquee.stepMs;
                    if (marquee.phase === 0 || marquee.phase === 2) {
                        if (marquee.elapsed >= marquee.endPauseMs) {
                            marquee.phase = (marquee.phase + 1) % 4;
                            marquee.elapsed = 0;
                        }
                        return;
                    }
                    const t = Math.min(1, marquee.elapsed / marquee.scrollDur);
                    const eased = marquee.ease(t);
                    label.x = marquee.phase === 1 ? -marquee.scrollDist * eased : -marquee.scrollDist * (1 - eased);
                    if (t >= 1) {
                        marquee.phase = (marquee.phase + 1) % 4;
                        marquee.elapsed = 0;
                    }
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
    Lib.HoverBridge {
        popup: popup
        widgetHovered: widgetHover.hovered
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
