// features/hm/wayland/quickshell/task-bar/lock/LockNotifications.qml
// Lock-native notification list. Reads notifSvc.groups, classifies each via
// `policy`, renders theme-styled cards. Task 4: full/sensitive/hidden tier
// rendering + trusted-tier action buttons. Task 5: cap to `maxCards` cards
// with a "+N more" footer, plus a hide-all panic toggle. See
// docs/lock-notifications/spec.md.
//
// PRIVACY: this renders on a LOCKED, unauthenticated screen. `modelData.body`
// and `modelData.image` must be referenced ONLY inside a `_vis === "full"`
// -gated ternary so the string is never even read below the full tier.
// `modelData.summary` must be referenced ONLY inside a `_vis !== "hidden"`
// -gated ternary, for the same reason. Do not "fix" this by adding a
// `visible:` guard around an unconditional `text: modelData.body` (or
// `.summary`) -- a hidden Text item still holds the string.
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: root
    property var notifications: null   // Lib.NotifService
    property var policy: null          // LockNotifyPolicy
    property var theme: null           // live ThemeEngine
    property real contentOpacity: 1.0
    // Hard ceiling on rendered cards; 0 = no ceiling, let `availableHeight`
    // decide alone. The real limit is normally the height budget (see Dynamic
    // fit below) -- this stays only as a belt-and-braces bound from config.
    property int maxCards: 0
    // Panic toggle: forces every card to the hidden tier (see
    // LockNotifyPolicy.classify's hideAll precedence). Privacy-increasing
    // only -- flipping it back off simply returns to normal
    // per-notification classification, which is itself capped at
    // `defaultMode` for the default tier. There is no path from here to a
    // wider mode than configured. Resets to false on every lock because this
    // component is instantiated fresh per WlSessionLockSurface -- no
    // persistence is added.
    property bool hideAll: false
    // Toggle callback for the global panic state, supplied by Lock.qml via
    // LockSurface. `hideAll` above is now purely a read of that shared
    // state -- the ONLY write path is this callback (see the eye toggle's
    // onClicked below), so one click hides every locked output, not just
    // this one.
    property var toggleHideAll: null

    // Vertical space this list may occupy, in px, measured from its own top
    // down to whatever must stay clear beneath it (the watermark). Supplied by
    // LockSurface, which owns the layout. <= 0 means "unbounded", so the list
    // falls back to the `maxCards` ceiling alone -- that is also the
    // standalone / unit-test case.
    property real availableHeight: 0

    readonly property var groups: (root.notifications && LockConfig.notifEnable) ? root.notifications.groups : []
    spacing: 8
    opacity: root.contentOpacity
    visible: root.groups.length > 0

    // Strip markup from a notification body (bodies may carry a small HTML
    // subset per the notification spec). Full-tier only -- see PRIVACY note.
    function _plain(s) { return s ? String(s).replace(/<[^>]*>/g, "").trim() : ""; }

    // Icon/image resolution: a real path / file: / image: URL passes through
    // as-is; a bare icon NAME must be resolved via Quickshell.iconPath or it
    // silently fails to load. Mirrors hub/NotifItem.qml's appIconUrl/imageUrl.
    function _resolveIconLike(v) {
        if (!v)
            return "";
        var s = String(v);
        if (s.startsWith("/") || s.startsWith("file:") || s.startsWith("image:"))
            return s;
        return Quickshell.iconPath(s, "");
    }
    function _iconUrl(appIcon) { return root._resolveIconLike(appIcon); }
    function _imageUrl(image) { return root._resolveIconLike(image); }

    // Count of hidden-tier notifications in a group's list (private tier, or
    // hideAll). Used for the group's "N hidden" line -- counts only, no
    // summary/body/image of a hidden notification is ever touched.
    function _hiddenCount(list) {
        if (!root.policy)
            return 0;
        var c = 0;
        for (var i = 0; i < list.length; i++)
            if (root.policy.classify(list[i], root.hideAll).visibility === "hidden")
                c++;
        return c;
    }

    // Flatten every group's notifications into a single ordered card list,
    // then cap to `maxCards`. Capping happens on the flat list (not per
    // group) so the limit is a true backlog-wide cap, matching the "+N more"
    // footer's count.
    readonly property var _flat: {
        var out = [];
        var gs = root.groups;
        for (var g = 0; g < gs.length; g++)
            for (var i = 0; i < gs[g].list.length; i++)
                out.push(gs[g].list[i]);
        return out;
    }
    // --- Dynamic fit ------------------------------------------------------
    // How many cards render is decided by the height BUDGET (`availableHeight`,
    // supplied by LockSurface), not by a fixed count: the watermark below must
    // never be overlapped or covered, and the list has to give space back when
    // the media widget appears or a weather alert grows above it -- both push
    // this block down, which shrinks the budget.
    //
    // Row heights are MODELLED here as a pure function of the notification
    // (`_cardHeight`), deliberately mirroring the delegate's layout below --
    // keep the two in step when either changes.
    //
    // DO NOT "improve" this by MEASURING the rendered cards and feeding the
    // result back into the slice length. That was tried and it is a real
    // binding loop: changing the slice makes the Repeater recreate its
    // delegates, whose height signals fire again and change the slice again.
    // Qt flags it as a loop on `_fitCount` and the resulting log spam grew the
    // shell to 12 GB RSS, starved the machine, and left the lock's IPC
    // unresponsive WHILE LOCKED. The reasoning that made it look safe ("a
    // shorter slice only drops trailing cards, so the remaining heights do not
    // change") is wrong, because re-slicing does not shorten the list in place
    // -- it rebuilds every delegate. `_fitCount` must stay a pure function of
    // the model, the budget, and the constants below.
    //
    readonly property real _hHeader: 22      // eye-toggle row
    readonly property real _hFooter: 18      // "+N more"
    readonly property real _hGroupHead: 20   // app icon + name + count
    readonly property real _hHiddenLine: 18  // "N hidden"
    readonly property real _hGroupSpacing: 4 // group-internal ColumnLayout spacing
    readonly property real _hCardPad: 12     // card padding around cardCol
    readonly property real _hSummary: 18     // 13px summary, single elided line
    readonly property real _hBodyLine: 16    // 12px body, one wrapped line
    readonly property real _hThumb: 64       // image thumb
    readonly property real _hActions: 19     // action-button row
    readonly property real _hCardSpacing: 3  // cardCol spacing
    // Body wrap estimate: the card is 260px wide and the body is 12px, so
    // ~40 characters land per line. Rounded so a long body errs TALL.
    readonly property int _bodyCharsPerLine: 40
    readonly property int _bodyMaxLines: 4   // matches the body's maximumLineCount

    // Height of one rendered card, from the same layout the delegate builds
    // below -- keep the two in step. Returns 0 for the hidden tier, which
    // renders no card at all.
    //
    // PRIVACY: for the full tier this reads `body`.length and the presence of
    // `image`/`actions` to size the card. That is a full-tier-gated read of
    // content already being rendered in full, and nothing here enters the
    // render tree. Below the full tier no body/image is touched at all -- see
    // the file-header PRIVACY note.
    function _cardHeight(n) {
        if (!root.policy)
            return 0;
        var vis = root.policy.classify(n, root.hideAll).visibility;
        if (vis === "hidden")
            return 0;
        var h = root._hCardPad + root._hSummary;
        if (vis === "full") {
            var body = root._plain(n.body);
            if (body.length > 0) {
                var lines = Math.min(root._bodyMaxLines,
                                     Math.ceil(body.length / root._bodyCharsPerLine));
                h += root._hCardSpacing + lines * root._hBodyLine;
            }
            if (n.image)
                h += root._hCardSpacing + root._hThumb;
            if (n.actions && n.actions.length > 0)
                h += root._hCardSpacing + root._hActions;
        }
        return h;
    }

    // Number of leading cards from `_flat` that fit the budget. Walks the flat
    // list in render order, charging each card its measured (or estimated)
    // height plus the chrome it brings with it -- a group header on each app
    // change, and one "N hidden" line per group containing hidden cards.
    readonly property int _fitCount: {
        var flat = root._flat;
        var ceiling = (root.maxCards > 0) ? Math.min(root.maxCards, flat.length) : flat.length;
        if (!(root.availableHeight > 0) || !root.policy)
            return ceiling;
        // The header and the "+N more" footer are reserved UNCONDITIONALLY.
        // Reserving the footer even when nothing overflows is what stops the
        // degenerate case where a list fills the budget exactly, the footer
        // then appears, and the total spills over the watermark.
        var budget = root.availableHeight
                   - (root._hHeader + root.spacing)
                   - (root._hFooter + root.spacing);
        var used = 0;
        var fit = 0;
        var prevApp = null;
        var chargedHidden = false;
        for (var i = 0; i < ceiling; i++) {
            var n = flat[i];
            var app = root._keyOf(n);
            var isNewApp = (app !== prevApp);
            var vis = root.policy.classify(n, root.hideAll).visibility;
            var cost = 0;
            if (isNewApp)
                cost += root._hGroupHead + (i > 0 ? root.spacing : 0);
            if (vis === "hidden") {
                if (isNewApp || !chargedHidden)
                    cost += root._hHiddenLine + root._hGroupSpacing;
            } else {
                cost += root._cardHeight(n) + root._hGroupSpacing;
            }
            if (used + cost > budget)
                break;
            used += cost;
            if (isNewApp) {
                prevApp = app;
                chargedHidden = false;
            }
            if (vis === "hidden")
                chargedHidden = true;
            fit++;
        }
        return fit;
    }

    readonly property int _overflow: Math.max(0, root._flat.length - root._fitCount)

    // Regroup the capped slice, mirroring NotifService.groupBy's shape and
    // key so the capped render looks identical to the uncapped one (same
    // app headers, same fallback bucket name).
    function _keyOf(n) { return (n.appName && String(n.appName).length) ? String(n.appName) : "Notifications"; }
    function _groupSlice(list) {
        var map = {};
        var order = [];
        for (var i = 0; i < list.length; i++) {
            var k = root._keyOf(list[i]);
            if (!map[k]) {
                map[k] = [];
                order.push(k);
            }
            map[k].push(list[i]);
        }
        return order.map(function (k) {
            return { app: k, list: map[k] };
        });
    }
    readonly property var _capped: root._groupSlice(root._flat.slice(0, root._fitCount))

    // List header: hide-all panic toggle. Eye (showing) / eye-slash (hidden)
    // Nerd Font glyph; clicking flips `hideAll`. See the `hideAll` doc
    // comment above for the tighten-only privacy semantics.
    RowLayout {
        Layout.alignment: Qt.AlignRight
        visible: root.groups.length > 0
        LockText {
            text: root.hideAll ? String.fromCodePoint(0xF070) : String.fromCodePoint(0xF06E)
            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14
            color: root.theme ? root.theme.textSecondary : "#a89984"
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: if (root.toggleHideAll) root.toggleHideAll()
            }
        }
    }

    Repeater {
        model: root._capped
        delegate: ColumnLayout {
            required property var modelData // {app, list}
            readonly property int _hidden: root._hiddenCount(modelData.list)
            Layout.alignment: Qt.AlignRight
            spacing: 4
            // app header
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 6
                Image {
                    source: (modelData.list[0] && modelData.list[0].appIcon) ? root._iconUrl(modelData.list[0].appIcon) : ""
                    sourceSize.width: 16; sourceSize.height: 16
                    visible: source != ""
                }
                LockText {
                    text: (modelData.app || "Notifications") + "  " + modelData.list.length
                    color: root.theme ? root.theme.textSecondary : "#a89984"
                    font.pixelSize: 12; font.bold: true
                }
            }
            // hidden-tier count line (private tier / hideAll): count only --
            // no summary/body/image of a hidden notification is ever read.
            LockText {
                Layout.alignment: Qt.AlignRight
                visible: _hidden > 0
                text: _hidden + " hidden"
                color: root.theme ? root.theme.textSecondary : "#a89984"
                font.pixelSize: 11; opacity: 0.8
            }
            Repeater {
                model: modelData.list
                delegate: Rectangle {
                    id: cardRect
                    required property var modelData // Notification
                    readonly property var cls: root.policy ? root.policy.classify(modelData, root.hideAll) : ({tier: "private", visibility: "hidden", interactive: false})
                    // HIDDEN tier: the card does not render at all. QtQuick.Layouts
                    // excludes invisible items from layout, so this collapses to
                    // zero size; the group's "N hidden" line above covers it.
                    visible: cardRect.cls.visibility !== "hidden"
                    Layout.alignment: Qt.AlignRight
                    Layout.preferredWidth: 260
                    implicitHeight: cardCol.implicitHeight + 12
                    radius: 8
                    color: root.theme ? root.theme.bgCard : "#282828"
                    opacity: 0.9
                    ColumnLayout {
                        id: cardCol
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 3
                        // resolved policy for this card, computed once
                        readonly property string _vis: cardRect.cls.visibility
                        readonly property bool _interactive: cardRect.cls.interactive

                        // summary line (sensitive AND full). `modelData.summary` is
                        // referenced ONLY inside this hidden-gated ternary -- a
                        // visible:false Text would still hold the string in the
                        // render tree, which is exactly the leak the file-header
                        // PRIVACY note forbids for body/image. See PRIVACY note.
                        LockText {
                            Layout.fillWidth: true
                            text: cardCol._vis !== "hidden" ? (modelData.summary || (modelData.appName || "Notification")) : ""
                            color: root.theme ? root.theme.textPrimary : "#ebdbb2"
                            font.pixelSize: 13; elide: Text.ElideRight
                        }
                        // BODY: full tier only. `modelData.body` is referenced ONLY
                        // inside this full-gated ternary -- see file-header PRIVACY note.
                        LockText {
                            Layout.fillWidth: true
                            visible: cardCol._vis === "full" && text.length > 0
                            text: cardCol._vis === "full" ? root._plain(modelData.body) : ""
                            color: root.theme ? root.theme.textSecondary : "#a89984"
                            font.pixelSize: 12; wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                        }
                        // IMAGE THUMB: full tier only. `modelData.image` is referenced
                        // ONLY inside this full-gated ternary -- see PRIVACY note.
                        Image {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 64
                            Layout.alignment: Qt.AlignLeft
                            visible: cardCol._vis === "full" && source != ""
                            source: cardCol._vis === "full" ? root._imageUrl(modelData.image) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: 128; sourceSize.height: 128
                        }
                        // ACTIONS: trusted tier only (cls.interactive). invoke()
                        // dials straight into the notification bus -- NO PAM gate.
                        RowLayout {
                            visible: cardCol._interactive
                            spacing: 6
                            Repeater {
                                model: cardCol._interactive ? modelData.actions : []
                                delegate: Rectangle {
                                    required property var modelData // NotificationAction
                                    radius: 6; color: root.theme ? root.theme.accent : "#87b158"
                                    implicitWidth: aLabel.implicitWidth + 16; implicitHeight: aLabel.implicitHeight + 8
                                    LockText {
                                        id: aLabel; anchors.centerIn: parent
                                        text: modelData.text; color: root.theme ? root.theme.textOnAccent : "#1d2021"
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: modelData.invoke()   // trusted-tier only; no PAM
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // "+N more" footer: notifications beyond the `maxCards` cap. Count only
    // -- no notification content from the overflow is ever read.
    LockText {
        Layout.alignment: Qt.AlignRight
        visible: root._overflow > 0
        text: "+" + root._overflow + " more"
        color: root.theme ? root.theme.textSecondary : "#a89984"
        font.pixelSize: 11; opacity: 0.8
    }
}
