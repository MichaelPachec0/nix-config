import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../lib" as Lib

// Full player popup shown on hover over the bar MediaWidget: album art, title,
// artist, a seekable progress bar (click/drag, when the player supports it), and
// prev/play-pause/next. A separate non-grab window so it takes clicks/drag; the
// widget keeps it alive via hovered/contentHovered. Player is injected by the
// widget (already picked), so no re-selection here.
PopupWindow {
    id: pop

    required property QtObject theme
    required property var barWindow
    required property var anchorItem
    // defaultPlayer is the bar widget's auto-pick; `player` is the source the
    // popup controls. Selection policy: `player` follows the auto-pick UNTIL the
    // user clicks a chip (userPicked = true), after which it STAYS on that choice
    // across opens/closes -- so reopening keeps your chosen source instead of
    // snapping back to the leftmost/default. The stick is released only if that
    // player disappears, falling back to auto-tracking.
    property MprisPlayer defaultPlayer: null
    property MprisPlayer player: null
    property bool userPicked: false
    // Active players (playing or paused) -> the switcher chips. Drop the
    // playerctld proxy, which mirrors the active player as a duplicate entry.
    readonly property var allPlayers: (Mpris.players.values || []).filter(function (p) {
        return p && p.playbackState !== MprisPlaybackState.Stopped && (p.dbusName || "").indexOf("playerctld") < 0;
    })

    // Track the auto-pick only while closed and the user hasn't chosen a chip.
    onDefaultPlayerChanged: if (!pop.visible && !pop.userPicked)
        pop.player = pop.defaultPlayer
    // If the chosen player disappears, release the stick and auto-track again.
    onAllPlayersChanged: if (pop.player === null || pop.allPlayers.indexOf(pop.player) < 0) {
        pop.userPicked = false;
        pop.player = pop.defaultPlayer || (pop.allPlayers.length ? pop.allPlayers[0] : null);
    }

    // Auto-switch: if the selected player stays not-playing for autoSwitchMs while
    // another player IS playing, give up the (usually stale) pick and switch to
    // the active one, reverting to auto-tracking. Configurable; 10s default.
    property int autoSwitchMs: 10000
    readonly property bool selectedPlaying: pop.player !== null && pop.player.playbackState === MprisPlaybackState.Playing
    readonly property var playingOthers: pop.allPlayers.filter(function (p) {
        return p !== pop.player && p.playbackState === MprisPlaybackState.Playing;
    })
    // Only while the popup is open: the auto-switch drops a stale pick you are
    // LOOKING at, not one you set and closed. Without the visible gate it fires
    // with the popup closed and silently overrides a pinned player, breaking the
    // "userPicked STAYS across opens/closes" contract (see the userPicked docs).
    Timer {
        interval: pop.autoSwitchMs
        repeat: true
        running: pop.visible && !pop.selectedPlaying && pop.playingOthers.length > 0
        onTriggered: {
            pop.player = pop.playingOthers[0];
            pop.userPicked = false;
        }
    }

    // True while the cursor is over the popup -- the widget reads this to keep it
    // open while moving between the bar and the popup.
    property bool contentHovered: false

    // Tabs: 0 = Now Playing, 1 = Queue, 2 = Playlists. effTab falls back to Now
    // Playing if the active tab's interface is unsupported for the current player.
    property int activeTab: 0
    readonly property int effTab: (pop.activeTab === 1 && !ex.supportsQueue) || (pop.activeTab === 2 && !ex.supportsPlaylists) ? 0 : pop.activeTab

    Lib.MprisExtras {
        id: ex
        bus: pop.player ? (pop.player.dbusName || "") : ""
        popupOpen: pop.visible
        queueWants: pop.visible && pop.effTab === 1
        playlistsWants: pop.visible && pop.effTab === 2
    }

    implicitWidth: 280
    implicitHeight: card.implicitHeight
    color: "transparent"
    visible: false
    grabFocus: false

    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Right

    function showPopup() {
        if (pop.visible)
            return;
        // Keep the user's chip choice; only seed from the auto-pick if unset.
        if (!pop.userPicked && pop.player === null)
            pop.player = pop.defaultPlayer;
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        // Keep the whole popup on-screen (clamp the left edge).
        pop.anchor.rect.x = Math.max(4, Math.min(x, pop.barWindow.width - pop.implicitWidth - 8));
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
        pop.visible = true;
    }
    function hide() {
        pop.visible = false;
    }

    // --- time ---
    readonly property bool isPlaying: pop.player && pop.player.playbackState === MprisPlaybackState.Playing
    readonly property real lenSec: pop.player ? (pop.player.length || 0) : 0
    property real posSec: 0
    property real dragFrac: -1 // >= 0 while scrubbing
    readonly property real displayFrac: pop.dragFrac >= 0 ? pop.dragFrac : (pop.lenSec > 0 ? Math.max(0, Math.min(1, pop.posSec / pop.lenSec)) : 0)

    onPlayerChanged: {
        pop.posSec = pop.player ? pop.player.position : 0;
        pop.activeTab = 0;
    }
    Timer {
        interval: 400
        repeat: true
        running: pop.visible && pop.player !== null
        triggeredOnStart: true
        onTriggered: if (pop.dragFrac < 0)
            pop.posSec = pop.player ? pop.player.position : 0
    }

    function fmt(s) {
        if (isNaN(s) || s < 0)
            return "0:00";
        var m = Math.floor(s / 60);
        var ss = Math.floor(s % 60);
        return m + ":" + (ss < 10 ? "0" : "") + ss;
    }

    // Round transport button (mirrors MediaCard).
    component CtlButton: Rectangle {
        id: ctl
        property int glyph: 0
        property int glyphSize: 16
        property bool primary: false
        property bool enabledAction: true
        property bool active: false // accent-tint the glyph (repeat/shuffle engaged)
        signal activated

        width: primary ? 46 : 34
        height: primary ? 46 : 34
        radius: width / 2
        color: primary ? Qt.rgba(pop.theme.accent.r, pop.theme.accent.g, pop.theme.accent.b, ctlHover.hovered ? 0.28 : 0.18) : (ctlHover.hovered ? pop.theme.bgItemHover : "transparent")
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
            color: ctl.active ? pop.theme.accent : (ctl.primary ? pop.theme.textPrimary : pop.theme.textSecondary)
            font.family: pop.theme.iconFont
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

    // Tab-strip chip (Now Playing / Queue / Playlists).
    component Tab: Rectangle {
        id: tabRect
        property string label: ""
        property int tabIndex: 0
        property bool shown: true
        visible: shown
        implicitHeight: 22
        implicitWidth: tabText.implicitWidth + 18
        radius: 8
        color: pop.effTab === tabRect.tabIndex ? pop.theme.accent : pop.theme.bgItem
        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
        Text {
            id: tabText
            anchors.centerIn: parent
            text: tabRect.label
            color: pop.effTab === tabRect.tabIndex ? pop.theme.textOnAccent : pop.theme.textSecondary
            font.family: pop.theme.textFont
            font.pixelSize: 10
            font.weight: pop.effTab === tabRect.tabIndex ? Font.DemiBold : Font.Normal
        }
        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: pop.activeTab = tabRect.tabIndex
        }
    }

    Rectangle {
        id: card
        implicitWidth: pop.width
        implicitHeight: col.implicitHeight + 22
        radius: pop.theme.radiusOuter
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border

        HoverHandler {
            onHoveredChanged: pop.contentHovered = hovered
        }

        ColumnLayout {
            id: col
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 11
            }
            spacing: 8

            // Player switcher chips (only when more than one player is active).
            RowLayout {
                Layout.fillWidth: true
                visible: pop.allPlayers.length > 1
                spacing: 6
                Repeater {
                    model: pop.allPlayers
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: modelData === pop.player
                        implicitHeight: 22
                        implicitWidth: chipLabel.implicitWidth + 18
                        radius: 11
                        color: sel ? pop.theme.accent : pop.theme.bgItem
                        border.width: 1
                        border.color: sel ? pop.theme.accent : pop.theme.border
                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }
                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: modelData.identity || "Player"
                            color: sel ? pop.theme.textOnAccent : pop.theme.textSecondary
                            font.family: pop.theme.textFont
                            font.pixelSize: 10
                            font.weight: sel ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: {
                                pop.player = modelData;
                                pop.userPicked = true; // stick to this choice
                            }
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }

            // Tab strip (Now Playing + tabs the player supports).
            RowLayout {
                Layout.fillWidth: true
                visible: ex.supportsQueue || ex.supportsPlaylists
                spacing: 6

                Tab {
                    label: "Now Playing"
                    tabIndex: 0
                }
                Tab {
                    label: "Queue"
                    tabIndex: 1
                    shown: ex.supportsQueue
                }
                Tab {
                    label: "Playlists"
                    tabIndex: 2
                    shown: ex.supportsPlaylists
                }
                Item {
                    Layout.fillWidth: true
                }
            }

            // Queue tab.
            ColumnLayout {
                Layout.fillWidth: true
                visible: pop.effTab === 1
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    visible: ex.queue.length === 0
                    text: "Queue empty"
                    color: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 12
                    topPadding: 6
                    bottomPadding: 6
                }
                ListView {
                    id: queueList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 260)
                    visible: ex.queue.length > 0
                    clip: true
                    spacing: 2
                    model: queueModel

                    // A stable ListModel updated IN PLACE from ex.queue. ncspot's radio
                    // rewrites ex.queue every couple of seconds; binding the ListView
                    // straight to that plain array made every rewrite a full model reset
                    // that snapped contentY to 0, so any centring fought a constant reset
                    // (the click-time jitter). Updating a persistent model by index
                    // (set/append/remove) preserves the scroll, so we only ever scroll on
                    // an explicit event: entering the view, the track changing, or a click.
                    ListModel { id: queueModel }
                    property string anchoredId: ""    // current track id we last centred on
                    property bool centerArmed: false  // force one centre once the queue loads
                    property bool userScrolled: false // suppress auto-follow while browsing
                    onMovementStarted: queueList.userScrolled = true

                    function syncQueueModel() {
                        var q = ex.queue;
                        var n = q.length;
                        for (var i = 0; i < n; ++i) {
                            var t = q[i];
                            var row = {
                                trackid: t.trackid || "",
                                title: t.title || "",
                                artist: t.artist || "",
                                art: t.art || "",
                                current: !!t.current,
                                played: !!t.played
                            };
                            if (i < queueModel.count) {
                                var m = queueModel.get(i);
                                if (m.trackid !== row.trackid || m.current !== row.current
                                    || m.played !== row.played || m.title !== row.title
                                    || m.artist !== row.artist || m.art !== row.art)
                                    queueModel.set(i, row);
                            } else {
                                queueModel.append(row);
                            }
                        }
                        while (queueModel.count > n)
                            queueModel.remove(queueModel.count - 1);
                    }
                    function currentIdx() {
                        for (var i = 0; i < ex.queue.length; ++i)
                            if (ex.queue[i].current)
                                return i;
                        return -1;
                    }
                    function currentId() {
                        var i = queueList.currentIdx();
                        return i >= 0 ? ex.queue[i].trackid : "";
                    }
                    // Scroll so row idx sits at the vertical centre. Fixed 40px rows +
                    // spacing, so compute contentY directly (deterministic).
                    function centerOnIndex(idx) {
                        var rowH = 40 + queueList.spacing;
                        var contentH = ex.queue.length * rowH - queueList.spacing;
                        var viewH = queueList.height;
                        if (viewH <= 0 || contentH <= viewH)
                            return; // everything fits: nothing to scroll
                        var target = idx * rowH - (viewH - 40) / 2;
                        queueList.contentY = Math.max(0, Math.min(target, contentH - viewH));
                    }
                    // After each in-place sync: entry forces a centre; otherwise only a
                    // track change re-centres, and only when the user isn't browsing.
                    function afterSync(forceCenter) {
                        var idx = queueList.currentIdx();
                        if (idx < 0)
                            return; // no current track yet; keep centerArmed for later
                        var cid = ex.queue[idx].trackid;
                        if (forceCenter) {
                            queueList.centerArmed = false;
                            queueList.userScrolled = false;
                            queueList.anchoredId = cid;
                            queueList.centerOnIndex(idx);
                        } else if (cid !== queueList.anchoredId) {
                            queueList.anchoredId = cid;
                            if (!queueList.userScrolled)
                                queueList.centerOnIndex(idx);
                        }
                    }
                    Component.onCompleted: {
                        queueList.syncQueueModel();
                        queueList.afterSync(true);
                    }
                    Connections {
                        target: ex
                        function onQueueWantsChanged() {
                            if (ex.queueWants) {
                                queueList.centerArmed = true;
                                queueList.userScrolled = false;
                                queueList.syncQueueModel();
                                queueList.afterSync(true);
                            }
                        }
                        function onQueueChanged() {
                            queueList.syncQueueModel();
                            queueList.afterSync(queueList.centerArmed);
                        }
                    }

                    delegate: Rectangle {
                        id: qrow
                        required property int index
                        required property string trackid
                        required property string title
                        required property string artist
                        required property string art
                        required property bool current
                        required property bool played
                        width: queueList.width
                        height: 40
                        radius: 6
                        color: qHover.hovered ? pop.theme.bgItemHover : (qrow.current ? Qt.rgba(pop.theme.accent.r, pop.theme.accent.g, pop.theme.accent.b, 0.16) : "transparent")
                        // Played tracks render dimmed; hovering one restores full
                        // opacity so it reads as clickable (jump back / remove).
                        opacity: (qrow.played && !qHover.hovered) ? 0.45 : 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 5
                            anchors.rightMargin: 6
                            spacing: 8
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                width: 30
                                height: 30
                                radius: 5
                                color: pop.theme.bgItem
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: qrow.art || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 60
                                    sourceSize.height: 60
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: qrow.title || "Unknown"
                                    color: qrow.current ? pop.theme.accent : pop.theme.textPrimary
                                    font.family: pop.theme.textFont
                                    font.pixelSize: 12
                                    font.weight: qrow.current ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: qrow.artist || ""
                                    color: pop.theme.textSecondary
                                    font.family: pop.theme.textFont
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                // Remove (x) -- visible on row hover.
                                visible: qHover.hovered
                                text: String.fromCodePoint(0xF0156) // close
                                color: pop.theme.textSecondary
                                font.family: pop.theme.iconFont
                                font.pixelSize: 13
                                TapHandler {
                                    // Own the tap on the (x): an exclusive grab on press
                                    // pre-empts the row-level TapHandler's passive grab, so
                                    // removing a track no longer also fires goTo. (Cursor is
                                    // covered by the row's qHover PointingHandCursor.)
                                    gesturePolicy: TapHandler.ExclusiveGrab
                                    onTapped: ex.remove(qrow.trackid)
                                }
                            }
                        }
                        HoverHandler {
                            id: qHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: {
                                // Centre on the clicked row; anchoredId stays the CURRENT
                                // track so a queue mutation during the ~2s switch window
                                // doesn't re-centre off it, and the stable model keeps the
                                // view here until this row starts playing.
                                queueList.userScrolled = false;
                                queueList.anchoredId = queueList.currentId();
                                queueList.centerOnIndex(qrow.index);
                                ex.goTo(qrow.trackid);
                            }
                        }
                    }
                }
            }

            // Playlists tab.
            ColumnLayout {
                Layout.fillWidth: true
                visible: pop.effTab === 2
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    visible: ex.playlists.length === 0
                    text: "No playlists"
                    color: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 12
                    topPadding: 6
                    bottomPadding: 6
                }
                ListView {
                    id: plList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 260)
                    visible: ex.playlists.length > 0
                    clip: true
                    spacing: 2
                    model: ex.playlists
                    delegate: Rectangle {
                        id: prow
                        required property var modelData
                        width: plList.width
                        height: 32
                        radius: 6
                        color: pHover.hovered ? pop.theme.bgItemHover : (prow.modelData.active ? Qt.rgba(pop.theme.accent.r, pop.theme.accent.g, pop.theme.accent.b, 0.16) : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8
                            // Real playlist icon (ncspot now serves Spotify art
                            // URLs in the Playlists interface); fall back to the
                            // generic playlist glyph while it loads or if absent.
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                width: 26
                                height: 26
                                radius: 5
                                color: pop.theme.bgItem
                                clip: true
                                Image {
                                    id: plIcon
                                    anchors.fill: parent
                                    source: prow.modelData.icon || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 52
                                    sourceSize.height: 52
                                    visible: plIcon.status === Image.Ready
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: plIcon.status !== Image.Ready
                                    text: String.fromCodePoint(0xF0279) // format-list-bulleted
                                    color: prow.modelData.active ? pop.theme.accent : pop.theme.textSecondary
                                    font.family: pop.theme.iconFont
                                    font.pixelSize: 14
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: prow.modelData.name || "Playlist"
                                color: prow.modelData.active ? pop.theme.accent : pop.theme.textPrimary
                                font.family: pop.theme.textFont
                                font.pixelSize: 12
                                font.weight: prow.modelData.active ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }
                        }
                        HoverHandler {
                            id: pHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: ex.activate(prow.modelData.path)
                        }
                    }
                }
            }

            // Art + title/artist
            RowLayout {
                visible: pop.effTab === 0
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 54
                    Layout.preferredHeight: 54
                    radius: 8
                    color: pop.theme.bgItem
                    clip: true
                    Text {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: String.fromCodePoint(0xF001)
                        color: pop.theme.textSecondary
                        font.family: pop.theme.iconFont
                        font.pixelSize: 24
                    }
                    Image {
                        id: art
                        anchors.fill: parent
                        source: pop.player ? (pop.player.trackArtUrl || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: 128
                        sourceSize.height: 128
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        text: pop.player ? (pop.player.trackTitle || "Unknown Title") : ""
                        color: pop.theme.textPrimary
                        font.family: pop.theme.textFont
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: pop.player ? (pop.player.trackArtist || "Unknown Artist") : ""
                        color: pop.theme.textSecondary
                        font.family: pop.theme.textFont
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: pop.player ? (pop.player.trackAlbum || "") : ""
                        visible: text !== ""
                        color: pop.theme.textSecondary
                        font.family: pop.theme.textFont
                        font.pixelSize: 11
                        opacity: 0.8
                        elide: Text.ElideRight
                    }
                }

                // Narrow controls column beside the metadata: shuffle over repeat.
                // Replaces the old centered row (which wasted a full-width row on two
                // buttons). Collapses to zero width when the player supports neither,
                // so the title/artist reclaim the space.
                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    visible: pop.player ? (pop.player.shuffleSupported || pop.player.loopSupported) : false

                    CtlButton {
                        glyph: 0xF049D // shuffle
                        glyphSize: 13
                        visible: pop.player ? pop.player.shuffleSupported : false
                        active: pop.player ? pop.player.shuffle : false
                        onActivated: if (pop.player)
                            pop.player.shuffle = !pop.player.shuffle
                    }
                    CtlButton {
                        // repeat: off -> all (Playlist) -> one (Track) -> off; the
                        // repeat-once glyph marks Track mode, else the plain repeat glyph.
                        glyph: (pop.player && pop.player.loopState === MprisLoopState.Track) ? 0xF0458 : 0xF0456
                        glyphSize: 13
                        visible: pop.player ? pop.player.loopSupported : false
                        active: pop.player ? pop.player.loopState !== MprisLoopState.None : false
                        onActivated: {
                            if (!pop.player)
                                return;
                            var s = pop.player.loopState;
                            pop.player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist : (s === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None);
                        }
                    }
                }
            }

            // Seek bar (click/drag to scrub when the player can seek).
            Item {
                visible: pop.effTab === 0
                Layout.fillWidth: true
                implicitHeight: 16

                readonly property bool canSeek: pop.player ? pop.player.canSeek : false

                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 3
                    color: pop.theme.bgItem

                    Rectangle {
                        width: parent.width * pop.displayFrac
                        height: parent.height
                        radius: 3
                        color: pop.theme.accent
                    }
                    Rectangle {
                        width: 12
                        height: 12
                        radius: 6
                        color: pop.theme.accent
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(parent.width - width, parent.width * pop.displayFrac - width / 2))
                        visible: parent.parent.canSeek && (seekArea.containsMouse || seekArea.pressed)
                    }
                }

                MouseArea {
                    id: seekArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: parent.canSeek
                    cursorShape: parent.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                    function fracAt(mx) {
                        return Math.max(0, Math.min(1, mx / width));
                    }
                    onPressed: mouse => pop.dragFrac = fracAt(mouse.x)
                    onPositionChanged: mouse => {
                        if (pressed)
                            pop.dragFrac = fracAt(mouse.x);
                    }
                    onReleased: mouse => {
                        var f = fracAt(mouse.x);
                        if (pop.player && pop.player.canSeek && pop.lenSec > 0) {
                            pop.player.position = f * pop.lenSec;
                            pop.posSec = f * pop.lenSec;
                        }
                        pop.dragFrac = -1;
                    }
                }
            }

            // Elapsed | transport controls | total -- one row, full width.
            RowLayout {
                visible: pop.effTab === 0
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: pop.fmt(pop.displayFrac * pop.lenSec)
                    color: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 10
                }
                Item {
                    Layout.fillWidth: true
                }
                RowLayout {
                    spacing: 12
                    CtlButton {
                        glyph: 0xF048 // step-backward
                        enabledAction: pop.player ? pop.player.canGoPrevious : false
                        onActivated: if (pop.player)
                            pop.player.previous()
                    }
                    CtlButton {
                        glyph: pop.isPlaying ? 0xF04C : 0xF04B
                        glyphSize: 19
                        primary: true
                        enabledAction: pop.player ? pop.player.canTogglePlaying : false
                        onActivated: if (pop.player)
                            pop.player.togglePlaying()
                    }
                    CtlButton {
                        glyph: 0xF051 // step-forward
                        enabledAction: pop.player ? pop.player.canGoNext : false
                        onActivated: if (pop.player)
                            pop.player.next()
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: pop.lenSec > 0.5 ? pop.fmt(pop.lenSec) : "--:--"
                    color: pop.theme.textSecondary
                    font.family: pop.theme.textFont
                    font.pixelSize: 10
                }
            }
        }
    }
}
