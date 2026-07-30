// features/hm/wayland/quickshell/task-bar/lock/LockNotifications.qml
// Lock-native notification list. Reads notifSvc.groups, classifies each via
// `policy`, renders theme-styled cards. Task 4: full/sensitive/hidden tier
// rendering + trusted-tier action buttons. Task 5: cap to `maxCards` cards
// with a "+N more" footer, plus a hide-all panic toggle. Task 6: one card per
// identical-content STACK (see lib/notifstack.js), with an "xN" count and an
// arrival stamp. See docs/lock-notifications/spec.md.
//
// PRIVACY: this renders on a LOCKED, unauthenticated screen. `cardRect.newest`
// is the stack's newest member's Notification object; its `.body` and
// `.image` must be referenced ONLY inside a `_vis === "full"`-gated ternary so
// the string is never even read below the full tier. `.summary` must be
// referenced ONLY inside a `_vis !== "hidden"`-gated ternary, for the same
// reason. Do not "fix" this by adding a `visible:` guard around an
// unconditional `text: cardRect.newest.body` (or `.summary`) -- a hidden Text
// item still holds the string.
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

    // Arrival-time formatter, injected by LockSurface as `NotifTime.fmtStamp`
    // with signature (nowMs, thenMs, use12h). Injected rather than imported
    // because `import "../lib/notiftime.js"` fails when notiffit-test.qml is the
    // quickshell -p entrypoint (the entrypoint's parent becomes the config root),
    // which would make the fit test unrunnable.
    property var stampFn: null
    // Shared 30s clock from NotifService. This MUST be read inside the stamp's
    // text binding, or the relative age would render once and never update.
    property double nowMs: 0
    // Lock clock preference (LockClockState.hour12), so the stamp matches the
    // big clock above it.
    property bool hour12: false

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

    // Notifications (not stacks) hidden in a group's stack list -- the "N
    // hidden" line counts what the user is not being shown, and a hidden stack
    // of 3 is 3 unseen notifications. Counts only; no summary/body/image of a
    // hidden notification is ever touched.
    function _hiddenCount(stacks) {
        if (!root.policy)
            return 0;
        var c = 0;
        for (var i = 0; i < stacks.length; i++)
            if (root._visOf(stacks[i]) === "hidden")
                c += stacks[i].count;
        return c;
    }

    // Notifications in a group's stack list, for the app header's count.
    function _groupTotal(stacks) {
        var c = 0;
        for (var i = 0; i < stacks.length; i++)
            c += stacks[i].count;
        return c;
    }

    // Every group's notifications collapsed into identical-content STACKS (see
    // lib/notifstack.js) and flattened into one ordered card list. One card per
    // stack, so a chatty source stops spending the height budget on visually
    // identical cards.
    readonly property var _flat: {
        var out = [];
        var gs = root.groups;
        if (!root.notifications)
            return out;
        for (var g = 0; g < gs.length; g++) {
            var stacks = root.notifications.stacksOf(gs[g].list);
            for (var i = 0; i < stacks.length; i++)
                out.push(stacks[i]);
        }
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
    readonly property real _hMetaRow: 15     // "x3  14:32 (2m ago)" line

    // Privacy tier for a whole stack: the STRICTEST of its members.
    //
    // notifstack.js keys on appName/desktopEntry/summary/body/urgency, which are
    // exactly the inputs the policy classifies on, so a stack is already
    // tier-homogeneous and this loop normally sees one answer. It is a
    // fail-closed backstop: if a key ever merged two tiers, the stack renders at
    // the tighter one rather than exposing the private member's content.
    function _rank(v) {
        return v === "hidden" ? 2 : (v === "sensitive" ? 1 : 0);
    }
    function _classifyStack(st) {
        if (!root.policy)
            return ({ tier: "private", visibility: "hidden", interactive: false });
        var worst = root.policy.classify(st.list[0], root.hideAll);
        for (var i = 1; i < st.list.length; i++) {
            var c = root.policy.classify(st.list[i], root.hideAll);
            if (root._rank(c.visibility) > root._rank(worst.visibility))
                worst = c;
        }
        // Actions come from the NEWEST member -- invoking a superseded
        // duplicate's action is meaningless -- and only while the stack as a
        // whole is at the full tier.
        var newest = root.policy.classify(st.list[0], root.hideAll);
        return {
            tier: worst.tier,
            visibility: worst.visibility,
            interactive: worst.visibility === "full" && newest.interactive
        };
    }
    function _visOf(st) {
        return root._classifyStack(st).visibility;
    }

    // Height of one rendered card, from the same layout the delegate builds
    // below -- keep the two in step. Returns 0 for the hidden tier, which
    // renders no card at all.
    //
    // PRIVACY: for the full tier this reads `body`.length and the presence of
    // `image`/`actions` to size the card. That is a full-tier-gated read of
    // content already being rendered in full, and nothing here enters the
    // render tree. Below the full tier no body/image is touched at all -- see
    // the file-header PRIVACY note.
    function _cardHeight(st) {
        if (!root.policy)
            return 0;
        var vis = root._visOf(st);
        if (vis === "hidden")
            return 0;
        var n = st.list[0];
        var h = root._hCardPad + root._hSummary;
        // Meta row: the count badge and/or the arrival stamp. Deterministic from
        // the model (no measurement), so the budget stays honest.
        if (st.count > 1 || st.newest > 0)
            h += root._hCardSpacing + root._hMetaRow;
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
            var vis = root._visOf(n);
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

    // "+N more" counts NOTIFICATIONS in the dropped stacks, not stacks -- the
    // user cares how many messages they are not seeing.
    readonly property int _overflow: {
        var c = 0;
        for (var i = root._fitCount; i < root._flat.length; i++)
            c += root._flat[i].count;
        return c;
    }

    // Regroup the capped slice of STACKS, mirroring NotifService.groupBy's shape
    // and key so the capped render looks identical to the uncapped one (same
    // app headers, same fallback bucket name).
    function _keyOf(st) {
        var n = st.list[0];
        return (n.appName && String(n.appName).length) ? String(n.appName) : "Notifications";
    }
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
                    source: (modelData.list[0] && modelData.list[0].list[0] && modelData.list[0].list[0].appIcon) ? root._iconUrl(modelData.list[0].list[0].appIcon) : ""
                    sourceSize.width: 16; sourceSize.height: 16
                    visible: source != ""
                }
                LockText {
                    text: (modelData.app || "Notifications") + "  " + root._groupTotal(modelData.list)
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
                    required property var modelData // a stack (see lib/notifstack.js)
                    // The stack's newest member supplies all rendered content.
                    readonly property var newest: cardRect.modelData.list[0]
                    readonly property var cls: root._classifyStack(cardRect.modelData)
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

                        // summary line (sensitive AND full). `newest.summary` is
                        // referenced ONLY inside this hidden-gated ternary -- a
                        // visible:false Text would still hold the string, which
                        // is exactly the leak the file-header PRIVACY note
                        // forbids for body/image. See PRIVACY note.
                        LockText {
                            Layout.fillWidth: true
                            text: cardCol._vis !== "hidden" ? (cardRect.newest.summary || (cardRect.newest.appName || "Notification")) : ""
                            color: root.theme ? root.theme.textPrimary : "#ebdbb2"
                            font.pixelSize: 13; elide: Text.ElideRight
                        }
                        // META ROW: how many identical notifications this card
                        // stands for, and when the newest arrived. Both are
                        // metadata (a count and a time), never content, so they
                        // are safe at the sensitive tier. The hidden tier's card
                        // is visible:false so this row never paints -- but note
                        // the bindings still EVALUATE, which is safe only
                        // because they read a count and a timestamp. Any content
                        // field added here still needs its own _vis gate.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: cardRect.modelData.count > 1 || cardRect.modelData.newest > 0
                            LockText {
                                visible: cardRect.modelData.count > 1
                                text: "x" + cardRect.modelData.count
                                color: root.theme ? root.theme.accent : "#87b158"
                                font.pixelSize: 11; font.bold: true
                            }
                            LockText {
                                Layout.fillWidth: true
                                // Reads root.nowMs so the age repaints on the
                                // shared 30s tick, and root.hour12 so it tracks
                                // the lock clock's 12/24h toggle.
                                text: root.stampFn ? root.stampFn(root.nowMs, cardRect.modelData.newest, root.hour12) : ""
                                color: root.theme ? root.theme.textSecondary : "#a89984"
                                font.pixelSize: 11; opacity: 0.8; elide: Text.ElideRight
                            }
                        }
                        // BODY: full tier only. `newest.body` is referenced ONLY
                        // inside this full-gated ternary -- see file-header PRIVACY note.
                        LockText {
                            Layout.fillWidth: true
                            visible: cardCol._vis === "full" && text.length > 0
                            text: cardCol._vis === "full" ? root._plain(cardRect.newest.body) : ""
                            color: root.theme ? root.theme.textSecondary : "#a89984"
                            font.pixelSize: 12; wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                        }
                        // IMAGE THUMB: full tier only. `newest.image` is referenced
                        // ONLY inside this full-gated ternary -- see PRIVACY note.
                        Image {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 64
                            Layout.alignment: Qt.AlignLeft
                            visible: cardCol._vis === "full" && source != ""
                            source: cardCol._vis === "full" ? root._imageUrl(cardRect.newest.image) : ""
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
                                model: cardCol._interactive ? cardRect.newest.actions : []
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
