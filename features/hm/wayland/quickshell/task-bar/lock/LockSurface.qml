// features/hm/wayland/quickshell/task-bar/lock/LockSurface.qml
// Per-output lock UI: backdrop + clock + password dots + failure feedback.
// Non-security presentation. All surfaces share the same `context`, so typing /
// feedback is mirrored across outputs.
import QtQuick
import Quickshell.Services.Mpris
import "../lib/weathericons.js" as WeatherIcons
import "../lib/weathercond.js" as WeatherCond

Item {
    id: root
    required property var context
    property string backdropSource: ""
    property var clockState: null
    property var weather: null // {temp, icon, desc, uv, conditions[], ...} or null; from Lock.qml's weatherPoll
    property var audio: null // Lib.AudioService, threaded from shell.qml via Lock.qml

    // Static Gruvbox accent object (mirrors lib/ThemeEngine.qml's fallback hex
    // values) for the UV/condition color helpers below -- the lock has no
    // FileView-backed theme, so this is a fixed palette rather than the live
    // ~/.config/theme/colors.json read.
    readonly property var wxTheme: ({
        textPrimary: "#ebdbb2", textSecondary: "#a89984",
        accentGreen: "#b8bb26", accentYellow: "#fabd2f",
        accentPurple: "#d3869b", accentRed: "#fb4934",
        accentOrange: "#fe8019", accentBlue: "#83a598"
    })

    // UV index band word / "7  High" label / severity colour -- copied
    // verbatim from desktop/WeatherPopup.qml:44-61 (pop.theme -> root.wxTheme,
    // pop.uvBand -> root.uvBand). Empty in -> empty out (row self-hides).
    function uvBand(v) {
        var n = parseInt(v);
        if (v === "" || isNaN(n))
            return "";
        return n <= 2 ? "Low" : (n <= 5 ? "Moderate" : (n <= 7 ? "High" : (n <= 10 ? "Very high" : "Extreme")));
    }
    function uvLabel(v) {
        var b = root.uvBand(v);
        return b === "" ? "" : (parseInt(v) + "  " + b);
    }
    function uvColor(v) {
        var n = parseInt(v);
        if (isNaN(n))
            return root.wxTheme.textPrimary;
        return n <= 2 ? root.wxTheme.accentGreen : (n <= 5 ? root.wxTheme.accentYellow : root.wxTheme.accentPurple);
    }

    // MPRIS media state -- mirrors desktop/MediaWidget.qml's players filter and
    // autoPlayer reduce verbatim (playing > paused > first). No re-selection UI
    // here (unlike the bar's MediaPopup player-switcher chips): the lock surface
    // always follows the auto-pick.
    readonly property var players: (Mpris.players.values || []).filter(function (p) {
        return p && (p.dbusName || "").indexOf("playerctld") < 0;
    })
    readonly property MprisPlayer autoPlayer: {
        var ps = root.players || [];
        for (var i = 0; i < ps.length; i++)
            if (ps[i] && ps[i].isPlaying)
                return ps[i];
        for (var j = 0; j < ps.length; j++)
            if (ps[j] && ps[j].playbackState === MprisPlaybackState.Paused)
                return ps[j];
        return ps.length ? ps[0] : null;
    }
    readonly property var mediaPlayer: autoPlayer

    LockBackdrop {
        anchors.fill: parent
        source: root.backdropSource
    }

    Column {
        id: column
        anchors.centerIn: parent
        spacing: 28

        // Clock -- click to toggle 24h/12h (persisted via clockState).
        LockText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#ebdbb2"
            font.pixelSize: 72
            font.bold: true
            text: (root.clockState && root.clockState.hour12)
                ? Qt.formatDateTime(clockTick.now, "h:mm AP")
                : Qt.formatDateTime(clockTick.now, "HH:mm")
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.clockState) root.clockState.hour12 = !root.clockState.hour12
            }
        }
        LockText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#a89984"
            font.pixelSize: 22
            text: Qt.formatDateTime(clockTick.now, "dddd, MMMM d")
        }

        // Password dots
        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 320; height: 52; radius: 26
            color: "#282828"; opacity: 0.85
            border.width: 2
            border.color: root.context.showFailure ? "#fb4934" : "#504945"

            Row {
                anchors.centerIn: parent
                spacing: 10
                Repeater {
                    model: root.context.currentText.length
                    Rectangle { width: 12; height: 12; radius: 6; color: "#ebdbb2" }
                }
            }

            // Hidden real input drives context.currentText.
            TextInput {
                id: input
                anchors.fill: parent
                opacity: 0
                focus: true
                echoMode: TextInput.Password
                text: root.context.currentText
                onTextChanged: root.context.currentText = text
                onAccepted: root.context.tryUnlock()
                Component.onCompleted: forceActiveFocus()
            }

            // Shake on failure.
            SequentialAnimation {
                id: shake
                loops: 1
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 12; duration: 40 }
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: -12; duration: 80 }
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
            }
        }

    }

    // Message line (PAM prompts / "Incorrect password"). Positioned OUTSIDE the
    // centered Column and anchored below it, so toggling it never reflows the
    // clock/field -- they stay put whether or not a message is showing.
    LockText {
        anchors.horizontalCenter: column.horizontalCenter
        anchors.top: column.bottom
        anchors.topMargin: 12
        visible: root.context.showFailure || root.context.statusMessage.length > 0
        color: (root.context.showFailure || root.context.statusIsError) ? "#fb4934" : "#a89984"
        font.pixelSize: 16
        text: root.context.showFailure
            ? ("Incorrect password" + (root.context.failCount > 1 ? " (" + root.context.failCount + ")" : ""))
            : root.context.statusMessage
    }

    // Weather widget (top-right, display-only). A NEW sibling of the centered
    // `column` above -- it never reflows the auth block. RELATIVE flow: a plain
    // Column, so when a condition/alert clears the stack shifts up (intended
    // for this corner, per docs/quickshell-lockscreen/lock-widgets.md). No
    // MouseArea/focus -- must never steal keyboard focus from the password
    // TextInput. Self-hides entirely while root.weather is null (no poll yet /
    // fetch failed).
    Column {
        id: weatherCol
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 28
        spacing: 6

        // Icon + temp. Icon glyph via weathericons.js, icon font matches
        // lib/ThemeEngine.qml's iconFont default ("JetBrainsMono Nerd Font").
        Row {
            anchors.right: parent.right
            spacing: 8
            visible: root.weather !== null
            LockText {
                text: WeatherIcons.glyph(root.weather ? root.weather.icon : "cloudy")
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 28
            }
            LockText {
                text: (root.weather ? root.weather.temp : "--") + String.fromCodePoint(0x00B0)
                font.pixelSize: 28
            }
        }

        // Condition description.
        LockText {
            anchors.right: parent.right
            horizontalAlignment: Text.AlignRight
            visible: text !== ""
            text: root.weather ? root.weather.desc : ""
            color: root.wxTheme.textSecondary
            font.pixelSize: 16
        }

        // UV index (hidden when the active provider supplies none).
        LockText {
            anchors.right: parent.right
            horizontalAlignment: Text.AlignRight
            visible: root.weather && root.uvLabel(root.weather.uv) !== ""
            text: "UV " + (root.weather ? root.uvLabel(root.weather.uv) : "")
            color: root.weather ? root.uvColor(root.weather.uv) : root.wxTheme.textPrimary
            font.pixelSize: 14
        }

        // Hourly forecast (up to 4h), mirroring the popup's hourly strip.
        // wx.hourly is [] for providers that supply none (owm/wttr) -> Row hides.
        Row {
            anchors.right: parent.right
            spacing: 12
            visible: root.weather !== null && root.weather.hourly !== undefined && root.weather.hourly.length > 0
            Repeater {
                model: root.weather ? root.weather.hourly.slice(0, 4) : []
                Column {
                    required property var modelData
                    spacing: 2
                    LockText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.h; color: root.wxTheme.textSecondary; font.pixelSize: 11 }
                    LockText { anchors.horizontalCenter: parent.horizontalCenter; text: WeatherIcons.glyph(modelData.icon); font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16 }
                    LockText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp + String.fromCodePoint(0x00B0); color: root.wxTheme.textPrimary; font.pixelSize: 12 }
                    LockText { anchors.horizontalCenter: parent.horizontalCenter; visible: modelData.uv !== ""; text: "UV " + modelData.uv; color: root.uvColor(modelData.uv); font.pixelSize: 10 }
                    LockText { anchors.horizontalCenter: parent.horizontalCenter; visible: modelData.precip !== "" && modelData.precip !== "0"; text: modelData.precip + "%"; color: root.wxTheme.textSecondary; font.pixelSize: 10; opacity: 0.85 }
                }
            }
        }

        // ALL active conditions/alerts, severity-sorted and color-coded
        // (incl. Pirate rain predictions and NWS alerts when that provider
        // wins the fetch) -- not filtered to severe/warn. Empty list -> no rows.
        Repeater {
            model: root.weather ? WeatherCond.sortBySeverity(root.weather.conditions) : []
            LockText {
                required property var modelData
                anchors.right: parent.right
                horizontalAlignment: Text.AlignRight
                text: modelData.label
                color: WeatherCond.color(root.wxTheme, modelData.kind, modelData.sev)
                font.pixelSize: 14
                font.bold: true
            }
        }
    }

    // Media widget (below weather, display-only + focus-neutral transport/volume
    // controls). A NEW sibling of `column`/`weatherCol` -- anchored below
    // weatherCol so it never reflows the centered auth block. Auto-picked MPRIS
    // player (playing > paused > first, see root.autoPlayer above) mirrors
    // desktop/MediaWidget.qml; art/title/artist/transport layout + glyph
    // codepoints mirror desktop/MediaPopup.qml. Self-hides while no MPRIS player
    // is active. No focus:true / forceActiveFocus anywhere below -- the password
    // TextInput keeps keyboard focus.
    Column {
        id: mediaCol
        anchors.top: weatherCol.bottom
        anchors.right: parent.right
        anchors.topMargin: 16
        anchors.rightMargin: 28
        spacing: 8
        visible: root.mediaPlayer !== null

        // Album art + title/artist. Art mirrors MediaPopup's rounded, clipped
        // Rectangle with a placeholder music-note glyph shown until (or unless)
        // trackArtUrl resolves.
        Row {
            anchors.right: parent.right
            spacing: 10

            Rectangle {
                width: 56
                height: 56
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.35)
                clip: true

                LockText {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    text: String.fromCodePoint(0xF001) // music note (MediaPopup placeholder)
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 22
                }
                Image {
                    id: art
                    anchors.fill: parent
                    source: root.mediaPlayer ? (root.mediaPlayer.trackArtUrl || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 112
                    sourceSize.height: 112
                }
            }

            Column {
                width: 220
                spacing: 2
                LockText {
                    width: parent.width
                    text: root.mediaPlayer ? (root.mediaPlayer.trackTitle || "Unknown Title") : ""
                    font.pixelSize: 15
                    font.bold: true
                    elide: Text.ElideRight
                }
                LockText {
                    width: parent.width
                    text: root.mediaPlayer ? (root.mediaPlayer.trackArtist || "Unknown Artist") : ""
                    color: root.wxTheme.textSecondary
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
            }
        }

        // Transport: prev / play-pause / next. Glyph codepoints copied verbatim
        // from desktop/MediaPopup.qml's CtlButton usage (step-backward 0xF048,
        // play 0xF04B / pause 0xF04C, step-forward 0xF051). Each glyph is wrapped
        // in a focus-neutral MouseArea (no focus:true) and dimmed when its
        // canGo*/canTogglePlaying is false, matching CtlButton's disabled opacity.
        Row {
            anchors.right: parent.right
            spacing: 18

            LockText {
                text: String.fromCodePoint(0xF048) // step-backward
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
                opacity: (root.mediaPlayer && root.mediaPlayer.canGoPrevious) ? 1.0 : 0.35
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.mediaPlayer && root.mediaPlayer.canGoPrevious)
                        root.mediaPlayer.previous()
                }
            }
            LockText {
                text: String.fromCodePoint((root.mediaPlayer && root.mediaPlayer.playbackState === MprisPlaybackState.Playing) ? 0xF04C : 0xF04B)
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 20
                opacity: (root.mediaPlayer && root.mediaPlayer.canTogglePlaying) ? 1.0 : 0.35
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.mediaPlayer && root.mediaPlayer.canTogglePlaying)
                        root.mediaPlayer.togglePlaying()
                }
            }
            LockText {
                text: String.fromCodePoint(0xF051) // step-forward
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
                opacity: (root.mediaPlayer && root.mediaPlayer.canGoNext) ? 1.0 : 0.35
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.mediaPlayer && root.mediaPlayer.canGoNext)
                        root.mediaPlayer.next()
                }
            }
        }

        // Volume readout: glyph + level (combined in one LockText via the icon
        // font, matching the bar's mixed glyph+percent Text idiom). Scroll
        // adjusts +/-5, click toggles mute. Guarded on root.audio !== null
        // (threaded shell.qml -> Lock.qml -> LockSurface); self-hides otherwise.
        LockText {
            anchors.right: parent.right
            visible: root.audio !== null
            text: root.audio ? (root.audio.volumeGlyph(root.audio.volume, root.audio.muted) + "  " + root.audio.volume + "%") : ""
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            color: root.wxTheme.textSecondary

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.audio) root.audio.toggleMute()
                onWheel: function (wheel) {
                    if (root.audio)
                        root.audio.stepVolume(wheel.angleDelta.y > 0 ? 5 : -5);
                }
            }
        }
    }

    // Re-focus the hidden input whenever this surface (re)appears.
    onVisibleChanged: if (visible) input.forceActiveFocus()

    Connections {
        target: root.context
        function onFailed() { shake.restart(); }
    }

    // 1s clock tick.
    QtObject { id: clockTick; property var now: new Date() }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: clockTick.now = new Date(); }
}
