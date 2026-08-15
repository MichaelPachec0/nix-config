// features/hm/wayland/quickshell/task-bar/lock/LockSurface.qml
// Per-output lock UI: backdrop + clock + password dots + failure feedback.
// Non-security presentation. All surfaces share the same `context`, so typing /
// feedback is mirrored across outputs.
import QtQuick
import Quickshell.Services.Mpris
import "../lib" as Lib
import "../lib/weathericons.js" as WeatherIcons
import "../lib/weathercond.js" as WeatherCond
import "../lib/notiftime.js" as NotifTime
import "../lib/routerfmt.js" as RouterFmt

Item {
    id: root
    required property var context
    property string backdropSource: ""
    property string screenName: "" // this output's name; keys the capture-holder registry
    property var registerHolder: null // Lock.qml's registerHolder(name, item)
    property var clockState: null
    property var weather: null // {temp, icon, desc, uv, conditions[], ...} or null; from Lock.qml's weatherPoll
    property var audio: null // Lib.AudioService, threaded from shell.qml via Lock.qml
    property var notifications: null // Lib.NotifService, threaded from shell.qml via Lock.qml
    property var policy: null // LockNotifyPolicy, instantiated in Lock.qml
    property bool notifHideAll: false // global hide-all panic state, from Lock.qml
    property var toggleNotifHideAll: null // Lock.qml's toggle function for notifHideAll
    property var security: null   // the Lock root, for its security state
    property var net: null // Lib.NetworkService, threaded from shell.qml via Lock.qml
    property var router: null // Lib.RouterService, threaded from shell.qml via Lock.qml
    property var bt: null // Lib.BluetoothService, threaded from shell.qml via Lock.qml

    // Lock-in / unlock-out animation, driven by Lock.qml. `revealed` false =
    // sharp backdrop + hidden widgets; true = blurred backdrop + visible
    // widgets. Durations are asymmetric: a slower reveal on lock, a quick
    // blur-out on unlock so the frozen (stale) backdrop is on screen sharp for
    // as little time as possible.
    property bool revealed: false
    readonly property int contentDuration: root.revealed ? 350 : 150
    readonly property int blurDuration: root.revealed ? 350 : 200
    // NOT readonly: the Behavior below animates this property, and an
    // animation has to write intermediate values into it. The binding sets the
    // target; the Behavior animates the approach.
    property real contentOpacity: root.revealed ? 1.0 : 0.0

    // Emitted once this surface exists, so Lock.qml can start the reveal only
    // after the surface's bindings have initialised at revealed == false --
    // a Behavior does not animate an initial binding value.
    signal surfaceReady

    Behavior on contentOpacity {
        NumberAnimation {
            duration: root.contentDuration
            easing.type: Easing.OutCubic
        }
    }

    // The lock's palette IS the taskbar's source of truth: a Lib.ThemeEngine in
    // Lock.qml reads the live ~/.config/theme/colors.json and is passed in as
    // `theme`, so every lock colour tracks the bar (incl. live theme changes).
    // `wxTheme` resolves to it; the static object is only a pre-load fallback
    // (mirrors ThemeEngine's Gruvbox defaults) and MUST carry every key we read.
    property var theme: null
    readonly property var wxTheme: root.theme ? root.theme : ({
        bgMain: "#1d2021", bgCard: "#282828", bgItem: "#3c3836", bgItemHover: "#504945",
        textPrimary: "#ebdbb2", textSecondary: "#a89984", textOnAccent: "#1d2021",
        accent: "#87b158", accentGreen: "#b8bb26", accentYellow: "#fabd2f",
        accentPurple: "#d3869b", accentRed: "#fb4934", accentOrange: "#fe8019",
        accentBlue: "#83a598"
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
    // autoPlayer reduce verbatim (playing > paused > first); still the default
    // source for `player` below.
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

    // Player switcher model -- mirrors desktop/MediaPopup.qml's
    // allPlayers/player/userPicked/onDefaultPlayerChanged/onAllPlayersChanged,
    // adapted for the lock: no `popup.visible` gate, since the LockSurface
    // itself only exists while locked (a fresh WlSessionLockSurface -- and
    // thus fresh `player`/`userPicked` state -- is created each lock, so the
    // pick resets naturally instead of needing an open/closed guard).
    //
    // Active players (playing or paused) -> the switcher chips. Drop the
    // playerctld proxy, which mirrors the active player as a duplicate entry.
    readonly property var allPlayers: (Mpris.players.values || []).filter(function (p) {
        return p && p.playbackState !== MprisPlaybackState.Stopped && (p.dbusName || "").indexOf("playerctld") < 0;
    })
    // Effective displayed player: follows the auto-pick UNTIL a chip is
    // clicked (userPicked = true), after which it stays on that choice for
    // the rest of this lock session. Released back to auto-tracking if the
    // picked player disappears.
    property var player: null
    property bool userPicked: false
    onAutoPlayerChanged: if (!root.userPicked)
        root.player = root.autoPlayer
    onAllPlayersChanged: {
        if (root.player === null || root.allPlayers.indexOf(root.player) < 0) {
            root.userPicked = false;
            root.player = root.autoPlayer || (root.allPlayers.length ? root.allPlayers[0] : null);
        }
    }
    Component.onCompleted: {
        root.player = root.autoPlayer;
        root.surfaceReady();
    }

    // Up-next queue for the picked player (optional MPRIS TrackList iface,
    // e.g. ncspot) -- mirrors the bar's Lib.MprisExtras wiring. popupOpen must
    // be true for the (cheap) caps poll to run and populate supportsQueue --
    // the lock has no popup to gate on, so it tracks "a player is picked"
    // instead of a fixed `true`, avoiding a poll with no bus to query.
    Lib.MprisExtras {
        id: mprisExtras
        bus: root.player ? (root.player.dbusName || "") : ""
        popupOpen: root.player !== null
        queueWants: root.player !== null
    }

    // Bottom limit for the right-hand widget stack. The watermark is a faithful
    // replica of the real activate-linux overlay (which the lock covers), so it
    // must never be overlapped or pushed off screen -- the notification list
    // treats this as a hard floor and drops cards instead. With the watermark
    // disabled the floor is the bottom edge, less a margin.
    readonly property real notifFloorY: watermarkBox.visible
        ? watermarkBox.y
        : (root.height - 28)

    LockBackdrop {
        anchors.fill: parent
        source: root.backdropSource
        theme: root.theme
        screenName: root.screenName
        registerHolder: root.registerHolder
        blurAmount: root.revealed ? 1.0 : 0.0
        animDuration: root.blurDuration
    }

    // NB: every top-level content child below (watermark, column, message,
    // weatherCol, mediaCol) -- i.e. everything except LockBackdrop -- binds
    // `opacity: root.contentOpacity` so the whole UI fades in on lock and out
    // on unlock as one. Add the same binding to any new top-level widget.
    // activate-linux watermark, positioned to MATCH the real overlay exactly.
    // hyprctl layers shows it as a fixed wlr-layer surface flush to the
    // bottom-right corner; activate-linux draws the title at (20,30) px font 24
    // and the subtitle at (20,55) px font 16 inside that box
    // (src/cairo_draw_text.c). We reproduce the box + those offsets so it lands
    // where the real overlay sits (hidden under the session lock). Title/
    // message/color/width/height come from LockConfig (Nix
    // quickshellLock.watermark, single source of truth also feeding the real
    // activate-linux CLI invocation in hyprland.nix/sway.nix) so the lock
    // replica never drifts from the desktop overlay. Plain Text, shadow-less --
    // a faithful subtle watermark, not legibility text. The (20,30)/(20,55)
    // offsets, 24/16px fonts, and "DejaVu Sans" family are activate-linux's
    // internal cairo layout constants (fixed by its source, not its CLI) and
    // stay hardcoded here.
    Item {
        id: watermarkBox
        opacity: root.contentOpacity
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: LockConfig.watermarkWidth
        height: LockConfig.watermarkHeight
        visible: LockConfig.watermarkEnable && LockConfig.watermarkTitle.length > 0

        // activate-linux uses cairo's toy API: cairo_select_font_face (default
        // "sans-serif" -> DejaVu Sans) + cairo_set_font_size (user units = px at
        // scale 1), and cairo_move_to sets the text BASELINE. QML Text positions
        // by the TOP, so shift each up by its font ascent to align the baseline
        // with the real overlay's (20,30) title / (20,55) subtitle.
        FontMetrics { id: fmT; font.family: "DejaVu Sans"; font.pixelSize: 24 }
        FontMetrics { id: fmS; font.family: "DejaVu Sans"; font.pixelSize: 16 }

        Text {
            x: 20
            y: 30 - fmT.ascent
            text: LockConfig.watermarkTitle
            color: LockConfig.watermarkColor
            font.family: "DejaVu Sans"
            font.pixelSize: 24
        }
        Text {
            x: 20
            y: 55 - fmS.ascent
            text: LockConfig.watermarkMessage
            color: LockConfig.watermarkColor
            font.family: "DejaVu Sans"
            font.pixelSize: 16
        }
    }

    Column {
        id: column
        opacity: root.contentOpacity
        anchors.centerIn: parent
        spacing: 28

        // Clock -- click to toggle 24h/12h (persisted via clockState).
        LockText {
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.wxTheme.textPrimary
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
            color: root.wxTheme.textSecondary
            font.pixelSize: 22
            text: Qt.formatDateTime(clockTick.now, "dddd, MMMM d")
        }

        // Password dots
        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 320; height: 52; radius: 26
            color: root.wxTheme.bgCard; opacity: 0.85
            border.width: 2
            border.color: root.context.showFailure ? root.wxTheme.accentRed : root.wxTheme.bgItemHover

            Row {
                anchors.centerIn: parent
                spacing: 10
                Repeater {
                    model: root.context.currentText.length
                    Rectangle { width: 12; height: 12; radius: 6; color: root.wxTheme.textPrimary }
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
        opacity: root.contentOpacity
        anchors.horizontalCenter: column.horizontalCenter
        anchors.top: column.bottom
        anchors.topMargin: 12
        visible: root.context.showFailure || root.context.statusMessage.length > 0
        color: (root.context.showFailure || root.context.statusIsError) ? root.wxTheme.accentRed : root.wxTheme.textSecondary
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
    // Security/presence signals (top-left; weatherCol mirrors this at
    // top-right). Metadata only -- see LockSecurity.qml.
    // Battery (top-left, above the security column). Display-only -- no
    // MouseArea or focus anywhere, the same rule every other lock widget
    // follows. Self-hides with ZERO HEIGHT on a machine with no laptop
    // battery, so the security column keeps the exact position it has
    // without this block.
    LockBattery {
        id: batteryCol
        opacity: root.contentOpacity
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 28
        // Carries hasBattery as well as the config flag: this binding REPLACES
        // the component's own `visible: root.hasBattery` rather than composing
        // with it, so dropping it here would render an empty block on a
        // machine with no laptop battery.
        visible: LockConfig.batEnable && batteryCol.hasBattery
        theme: root.wxTheme
        contentOpacity: root.contentOpacity
        lowPercent: LockConfig.batLowPercent
    }

    // Connectivity (top-left, below the battery block). Display-only -- no
    // MouseArea or focus anywhere, the same rule every other lock widget
    // follows. Collapses to zero height when it has nothing to report.
    LockNetwork {
        id: networkCol
        opacity: root.contentOpacity
        anchors.top: batteryCol.bottom
        anchors.left: parent.left
        anchors.leftMargin: 28
        anchors.topMargin: batteryCol.visible ? 10 : 0
        theme: root.wxTheme
        contentOpacity: root.contentOpacity
        net: root.net
        router: root.router
        bt: root.bt
        // Injected, not imported: lib/ falls outside the config root when
        // locknet-test.qml is the quickshell -p entrypoint. Same reason as
        // LockSecurity's stampFn.
        qualityFn: RouterFmt.quality
        // Carries hasAny as well as the config flag: an outer binding REPLACES
        // the component's own `visible: root.hasAny` rather than composing with
        // it, so dropping it would render an empty block.
        visible: LockConfig.netEnable && networkCol.hasAny
        showSsid: LockConfig.netShowSsid
        showRouter: LockConfig.netShowRouter
        showBluetooth: LockConfig.netShowBluetooth
    }

    LockSecurity {
        id: securityCol
        opacity: root.contentOpacity
        // Anchored below the battery block rather than to parent.top. With the
        // battery hidden its height is 0 and its bottom sits at the 28px top
        // margin, so a 0 top margin here puts this column at exactly the y it
        // had before the battery existed.
        anchors.top: networkCol.bottom
        anchors.left: parent.left
        anchors.leftMargin: 28
        anchors.topMargin: networkCol.visible ? 10 : 0
        visible: LockConfig.secEnable
        theme: root.wxTheme
        contentOpacity: root.contentOpacity
        castAtLock: root.security ? root.security.castAtLock : false
        // Gated on secScreencastPoll HERE, at the consumer, rather than by
        // touching the poll's `running` in Lock.qml -- uptime/sessions come
        // from the same probe tick and must keep working even with the
        // screencast half of the feature switched off. This is what makes
        // "casts is null when the poll is off" (LockConfig doc + the comment
        // in LockSecurity.qml) actually true, instead of only true when the
        // probe happens to fail.
        casts: (root.security && LockConfig.secScreencastPoll) ? root.security.secCasts : null
        pollEnabled: LockConfig.secScreencastPoll
        // NOT gated on secScreencastPoll: that option is about SCREEN capture,
        // and the camera/mic rows are a different signal from a different
        // detector (an fd scan and an exact media.class match). Folding them
        // under the screencast switch would silently drop device coverage for
        // anyone who opted out of the screen poll alone.
        cams: root.security ? root.security.secCams : null
        mics: root.security ? root.security.secMics : null
        showDevices: LockConfig.secShowDevices
        probed: root.security ? root.security.secProbed : false
        graceExpired: root.security ? root.security.secGraceExpired : false
        fails: root.security ? root.security.failsThisLock : 0
        otherUsers: root.security ? root.security.secOtherUsers : 0
        uptimeSec: root.security ? root.security.secUptimeSec : 0
        lastUnlockMs: root.security ? root.security.lockSecurityLastUnlockMs : 0
        ownerText: LockConfig.secOwnerText
        showUptime: LockConfig.secShowUptime
        showLastUnlock: LockConfig.secShowLastUnlock
        stampFn: NotifTime.fmtStamp
        // The security column is ALWAYS visible (unlike LockNotifications
        // below, whose cards only render while the list is non-empty), so it
        // cannot use the shared NotifService tick: that Timer's `running` is
        // gated on items/toasts being non-empty and otherwise sits frozen at
        // whatever Date.now() was when the shell started -- a "Last unlock"
        // relative time computed against a dead clock can go negative and
        // clamp to a false "just now". Use the surface's own live 1s tick
        // instead (see clockTick at the bottom of this file).
        nowMs: clockTick.now.getTime()
        hour12: root.clockState ? root.clockState.hour12 : false
    }

    Column {
        id: weatherCol
        opacity: root.contentOpacity
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
                color: root.wxTheme.textPrimary
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 28
            }
            LockText {
                text: (root.weather ? root.weather.temp : "--") + String.fromCodePoint(0x00B0)
                color: root.wxTheme.textPrimary
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
                    LockText { anchors.horizontalCenter: parent.horizontalCenter; text: WeatherIcons.glyph(modelData.icon); color: root.wxTheme.textPrimary; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16 }
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

    // Media widget (below weather, display-only + focus-neutral transport/
    // switcher/queue/volume controls). A NEW sibling of `column`/`weatherCol`
    // -- anchored below weatherCol so it never reflows the centered auth
    // block. root.player defaults to the auto-pick (playing > paused > first,
    // see root.autoPlayer above) but is settable via the chip switcher below
    // (root.userPicked); art/title/artist/transport/chip/queue layout + glyph
    // codepoints mirror desktop/MediaPopup.qml. Self-hides while no MPRIS
    // player is active. No focus:true / forceActiveFocus anywhere below --
    // the password TextInput keeps keyboard focus.
    Column {
        id: mediaCol
        opacity: root.contentOpacity
        anchors.top: weatherCol.bottom
        anchors.right: parent.right
        anchors.topMargin: 16
        anchors.rightMargin: 28
        spacing: 8
        visible: root.player !== null

        // Player switcher chips (only shown when more than one player is
        // active). Mirrors MediaPopup.qml's chip Repeater: `modelData.identity`
        // label, tinted background for the selected chip, sticky pick via
        // userPicked (see root.player/root.userPicked above). Focus-neutral
        // (no focus:true) -- the password field keeps keyboard focus.
        Row {
            anchors.right: parent.right
            spacing: 6
            visible: root.allPlayers.length > 1

            Repeater {
                model: root.allPlayers
                Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool sel: modelData === root.player
                    implicitHeight: 22
                    implicitWidth: chipLabel.implicitWidth + 16
                    radius: 11
                    color: chip.sel ? root.wxTheme.accent : root.wxTheme.bgItem

                    LockText {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: chip.modelData.identity || "Player"
                        color: chip.sel ? root.wxTheme.textOnAccent : root.wxTheme.textSecondary
                        font.pixelSize: 12
                        // Soft glow in the popup's accent (the chips' highlight)
                        // instead of the strong black default, which overpowers
                        // the small label.
                        shadowColor: root.wxTheme.accent
                        shadowRadius: 3
                        shadowOffset: 0
                        shadowOpacity: 0.35
                        outlineOpacity: 0
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.player = chip.modelData;
                            root.userPicked = true;
                        }
                    }
                }
            }
        }

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
                    color: root.wxTheme.textSecondary
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 22
                }
                Image {
                    id: art
                    anchors.fill: parent
                    source: root.player ? (root.player.trackArtUrl || "") : ""
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
                    text: root.player ? (root.player.trackTitle || "Unknown Title") : ""
                    color: root.wxTheme.textPrimary
                    font.pixelSize: 15
                    font.bold: true
                    elide: Text.ElideRight
                }
                LockText {
                    width: parent.width
                    text: root.player ? (root.player.trackArtist || "Unknown Artist") : ""
                    color: root.wxTheme.textSecondary
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
            }
        }

        // Transport: shuffle / prev / play-pause / next / repeat. Glyph
        // codepoints copied verbatim from desktop/MediaPopup.qml's CtlButton
        // usage (shuffle 0xF049D, step-backward 0xF048, play 0xF04B / pause
        // 0xF04C, step-forward 0xF051, repeat 0xF0456 / repeat-once 0xF0458).
        // Each glyph is a focus-neutral MouseArea (no focus:true). prev/play-
        // pause/next dim when their canGo*/canTogglePlaying is false
        // (matching CtlButton's disabled opacity); shuffle/repeat are
        // accent-tinted when engaged and hidden entirely when the player
        // doesn't support them (MediaPopup.qml gates the same way). The engaged
        // tint uses wxTheme.accent (#87b158, the MPRIS popup's accent), matching
        // the switcher's selected chip and the queue's "current track".
        Row {
            anchors.right: parent.right
            spacing: 18

            // Shuffle -- first child (before prev).
            LockText {
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
                visible: root.player && root.player.shuffleSupported
                text: String.fromCodePoint(0xF049D)
                color: (root.player && root.player.shuffle) ? root.wxTheme.accent : root.wxTheme.textSecondary
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.player && root.player.shuffleSupported)
                        root.player.shuffle = !root.player.shuffle
                }
            }

            LockText {
                text: String.fromCodePoint(0xF048) // step-backward
                color: root.wxTheme.textPrimary
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
                opacity: (root.player && root.player.canGoPrevious) ? 1.0 : 0.35
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.player && root.player.canGoPrevious)
                        root.player.previous()
                }
            }
            LockText {
                text: String.fromCodePoint((root.player && root.player.playbackState === MprisPlaybackState.Playing) ? 0xF04C : 0xF04B)
                color: root.wxTheme.textPrimary
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 20
                opacity: (root.player && root.player.canTogglePlaying) ? 1.0 : 0.35
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.player && root.player.canTogglePlaying)
                        root.player.togglePlaying()
                }
            }
            LockText {
                text: String.fromCodePoint(0xF051) // step-forward
                color: root.wxTheme.textPrimary
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
                opacity: (root.player && root.player.canGoNext) ? 1.0 : 0.35
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.player && root.player.canGoNext)
                        root.player.next()
                }
            }

            // Repeat -- last child (after next). Cycles off -> all (Playlist)
            // -> one (Track) -> off; the repeat-once glyph marks Track mode.
            LockText {
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
                visible: root.player && root.player.loopSupported
                text: String.fromCodePoint((root.player && root.player.loopState === MprisLoopState.Track) ? 0xF0458 : 0xF0456)
                color: (root.player && root.player.loopState !== MprisLoopState.None) ? root.wxTheme.accent : root.wxTheme.textSecondary
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!root.player || !root.player.loopSupported)
                            return;
                        var s = root.player.loopState;
                        root.player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist
                            : (s === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None);
                    }
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

        // Up-next queue (up to 4 tracks) via Lib.MprisExtras -- only for
        // players implementing the optional MPRIS TrackList interface (e.g.
        // ncspot); self-hides entirely otherwise (empty queue or unsupported).
        // Display-only except a focus-neutral tap-to-jump, mirroring the
        // queue rows' click-to-goTo + ~30x30 art thumbnail in MediaPopup.qml.
        Column {
            anchors.right: parent.right
            spacing: 6
            visible: mprisExtras.supportsQueue && mprisExtras.queue && mprisExtras.queue.length > 0

            Repeater {
                model: mprisExtras.queue ? mprisExtras.queue.slice(0, 4) : []
                Row {
                    id: qrow
                    required property var modelData
                    anchors.right: parent.right
                    spacing: 8

                    // TapHandler (not a MouseArea) so it doesn't claim a Row
                    // layout slot and stays focus-neutral.
                    TapHandler { onTapped: mprisExtras.goTo(qrow.modelData.trackid) }

                    // Art on the LEFT of the row, mirroring MediaPopup's queue.
                    Rectangle {
                        width: 28; height: 28; radius: 4; clip: true
                        color: Qt.rgba(0, 0, 0, 0.35)
                        Image {
                            anchors.fill: parent
                            source: qrow.modelData.art || ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: 56
                            sourceSize.height: 56
                        }
                    }
                    LockText {
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignLeft
                        width: 200
                        text: (qrow.modelData.title || "") + (qrow.modelData.artist ? "  -  " + qrow.modelData.artist : "")
                        color: qrow.modelData.current ? root.wxTheme.accent : root.wxTheme.textSecondary
                        font.pixelSize: 12
                        font.bold: qrow.modelData.current === true
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // Notification backlog (bottom-right column, below media, above the
    // watermark). Task 3: sensitive shape only -- see LockNotifications.qml.
    LockNotifications {
        id: notifBlock
        // Anchor to whichever widget above is actually on screen: mediaCol is a
        // plain Column, so while invisible it still reports its content height --
        // anchoring to it unconditionally strands a media-sized gap here
        // whenever no player is active.
        anchors.top: mediaCol.visible ? mediaCol.bottom : weatherCol.bottom
        anchors.right: parent.right
        anchors.topMargin: 16
        anchors.rightMargin: 28
        notifications: root.notifications
        policy: root.policy
        theme: root.theme
        contentOpacity: root.contentOpacity
        maxCards: LockConfig.notifMaxCards
        // Dynamic vertical budget: everything between this block's own top and
        // the watermark floor. The anchor chain above already pushes the block
        // down when weatherCol grows an alert row or mediaCol appears, so
        // binding the budget to `y` is what makes the list hand space back to
        // those widgets automatically. This cannot loop: `y` is resolved by the
        // anchor above and the budget only feeds this block's own height.
        availableHeight: Math.max(0, root.notifFloorY - notifBlock.y - 16)
        hideAll: root.notifHideAll
        toggleHideAll: root.toggleNotifHideAll
        // Injected rather than imported by LockNotifications -- see the stampFn
        // doc comment there for why (the fit test's import sandbox).
        stampFn: NotifTime.fmtStamp
        nowMs: root.notifications ? root.notifications.nowMs : 0
        hour12: root.clockState ? root.clockState.hour12 : false
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
