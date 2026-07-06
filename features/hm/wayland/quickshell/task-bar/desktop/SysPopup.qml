import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../lib" as Lib

// System stats popup shown on hover over the bar CPU/RAM block. Read-only.
// Mirrors RouterPopup's anchor/hover/reclamp. All text JetBrainsMono; glyphs faFont.
// Layout mode (0=tall 1=tabs 2=grid) persisted in sys-ui.json via CalState idiom.
PopupWindow {
    id: pop
    required property QtObject theme
    required property var stats
    required property var barWindow
    required property var anchorItem
    property bool contentHovered: cardHover.hovered

    readonly property string _stateDir: (Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    onImplicitWidthChanged: if (pop.visible) Qt.callLater(pop.reclamp)
    color: "transparent"
    visible: false
    grabFocus: false
    anchor.window: pop.barWindow
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Right

    function reclamp() {
        var x = pop.anchorItem.mapToItem(null, 0, 0).x;
        pop.anchor.rect.x = Math.max(4, Math.min(x, pop.barWindow.width - pop.implicitWidth - 8));
        pop.anchor.rect.y = pop.barWindow.height + 4;
        pop.anchor.rect.width = 0;
        pop.anchor.rect.height = 0;
    }
    function show() { if (!pop.visible) { pop.reclamp(); pop.visible = true; } }
    function hide() { pop.visible = false; }

    function fmtUptime(s) {
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        return h > 0 ? (h + "h " + m + "m") : (m + "m");
    }

    // Persistence: layout mode (0=tall 1=tabs 2=grid) written to sys-ui.json
    Process { running: true; command: ["mkdir", "-p", pop._stateDir] }
    FileView {
        id: uiFile
        path: pop._stateDir + "/sys-ui.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        Component.onCompleted: reload()
        JsonAdapter { id: uiAdapter; property int layout: 0 }
    }

    Lib.GpuStats      { id: gpu;     active: pop.visible }
    Lib.DiskStats     { id: disk;    active: pop.visible }
    Lib.NetStats      { id: net;     active: pop.visible }
    Lib.SensorStats   { id: sensors; active: pop.visible }
    Lib.RyzenSmuStats { id: smu;     active: pop.visible }

    Rectangle {
        id: card
        // Grid (two-column) mode needs more width so the columns are not cramped.
        implicitWidth: uiAdapter.layout === 2 ? 600 : 420
        implicitHeight: col.implicitHeight + 24
        radius: pop.theme.radiusOuter
        color: pop.theme.bgCard
        border.width: 1
        border.color: pop.theme.border
        HoverHandler { id: cardHover }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8

            // --- Header ---
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "System"
                    font.family: pop.theme.iconFont; font.pixelSize: 13; font.weight: Font.Bold
                    color: pop.theme.textPrimary
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "up " + pop.fmtUptime(pop.stats.uptime)
                    font.family: pop.theme.iconFont; font.pixelSize: 11
                    color: pop.theme.textSecondary
                }
                // Layout switcher: tall / tabs / grid
                Rectangle {
                    implicitWidth: _sw0.implicitWidth + 8; implicitHeight: 14; radius: 3
                    color: uiAdapter.layout === 0 ? pop.theme.accent : "transparent"
                    Text { id: _sw0; anchors.centerIn: parent; text: "tall"; font.family: pop.theme.iconFont; font.pixelSize: 9; color: uiAdapter.layout === 0 ? pop.theme.bgCard : pop.theme.textSecondary }
                    MouseArea { anchors.fill: parent; onClicked: uiAdapter.layout = 0 }
                }
                Rectangle {
                    implicitWidth: _sw1.implicitWidth + 8; implicitHeight: 14; radius: 3
                    color: uiAdapter.layout === 1 ? pop.theme.accent : "transparent"
                    Text { id: _sw1; anchors.centerIn: parent; text: "tabs"; font.family: pop.theme.iconFont; font.pixelSize: 9; color: uiAdapter.layout === 1 ? pop.theme.bgCard : pop.theme.textSecondary }
                    MouseArea { anchors.fill: parent; onClicked: uiAdapter.layout = 1 }
                }
                Rectangle {
                    implicitWidth: _sw2.implicitWidth + 8; implicitHeight: 14; radius: 3
                    color: uiAdapter.layout === 2 ? pop.theme.accent : "transparent"
                    Text { id: _sw2; anchors.centerIn: parent; text: "grid"; font.family: pop.theme.iconFont; font.pixelSize: 9; color: uiAdapter.layout === 2 ? pop.theme.bgCard : pop.theme.textSecondary }
                    MouseArea { anchors.fill: parent; onClicked: uiAdapter.layout = 2 }
                }
            }

            // --- Layout switcher body ---
            // Only the active layout is visible, so the card sizes to IT (a
            // StackLayout reserves the tallest layout's height -> dead space in
            // the compact modes; a Loader floods the log with construction-order
            // "undefined provider" transients). All three instantiate once at
            // load; the ColumnLayout collapses the two hidden ones.
            SysLayoutTall   { Layout.fillWidth: true; visible: uiAdapter.layout === 0; theme: pop.theme; stats: pop.stats; gpu: gpu; disk: disk; net: net; sensors: sensors; smu: smu }
            SysLayoutTabs   { Layout.fillWidth: true; visible: uiAdapter.layout === 1; theme: pop.theme; stats: pop.stats; gpu: gpu; disk: disk; net: net; sensors: sensors; smu: smu }
            SysLayoutTwoCol { Layout.fillWidth: true; visible: uiAdapter.layout === 2; theme: pop.theme; stats: pop.stats; gpu: gpu; disk: disk; net: net; sensors: sensors; smu: smu }
        }
    }
}
