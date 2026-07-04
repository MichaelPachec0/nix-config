import QtQuick
import QtQuick.Layouts
import Quickshell
import "../lib/sysfmt.js" as SysFmt

// System stats popup shown on hover over the bar CPU/RAM block. Read-only.
// Mirrors RouterPopup's anchor/hover/reclamp. All text JetBrainsMono; glyphs faFont.
PopupWindow {
    id: pop
    required property QtObject theme
    required property var stats
    required property var barWindow
    required property var anchorItem
    property bool contentHovered: cardHover.hovered

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

    function sevColor(sev) {
        return sev === "good" ? pop.theme.accentGreen
             : sev === "fair" ? pop.theme.accentYellow : pop.theme.accentRed;
    }
    function fmtUptime(s) {
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        return h > 0 ? (h + "h " + m + "m") : (m + "m");
    }

    Rectangle {
        id: card
        implicitWidth: 420
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
            }

            // --- CPU section ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: "CPU " + Math.round(pop.stats.cpuPct) + "%"
                    font.family: pop.theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: pop.sevColor(SysFmt.severity("cpu", pop.stats.cpuPct))
                }
                Text {
                    text: "load " + (pop.stats.load[0] || 0).toFixed(2) + " "
                        + (pop.stats.load[1] || 0).toFixed(2) + " " + (pop.stats.load[2] || 0).toFixed(2)
                    font.family: pop.theme.iconFont; font.pixelSize: 11
                    color: pop.theme.textSecondary
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "zen " + Math.round(pop.stats.cpuTemp) + " C"
                    font.family: pop.theme.iconFont; font.pixelSize: 11
                    color: pop.sevColor(SysFmt.severity("temp", pop.stats.cpuTemp))
                }
            }
            // Per-core mini bars.
            Row {
                Layout.fillWidth: true
                spacing: 2
                Repeater {
                    model: pop.stats.perCore
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: 6
                        height: 16
                        radius: 1
                        color: Qt.rgba(pop.theme.textSecondary.r, pop.theme.textSecondary.g,
                                       pop.theme.textSecondary.b, 0.2)
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Math.max(1, parent.height * modelData / 100)
                            radius: 1
                            color: pop.sevColor(SysFmt.severity("cpu", modelData))
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: pop.theme.border }

            // --- Memory section ---
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Memory  " + SysFmt.fmtKB(pop.stats.mem.usedKB || 0) + " / "
                        + SysFmt.fmtKB(pop.stats.mem.totalKB || 0) + "  (" + (pop.stats.mem.usedPct || 0) + "%)"
                    font.family: pop.theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: pop.sevColor(SysFmt.severity("mem", pop.stats.mem.usedPct))
                }
            }
            // Segmented bar: used | cached | free.
            Rectangle {
                Layout.fillWidth: true
                height: 10
                radius: 3
                color: Qt.rgba(pop.theme.textSecondary.r, pop.theme.textSecondary.g,
                               pop.theme.textSecondary.b, 0.15)
                readonly property real total: (pop.stats.mem.totalKB || 1)
                Row {
                    anchors.fill: parent
                    Rectangle {
                        width: parent.width * (pop.stats.mem.usedKB || 0) / parent.parent.total
                        height: parent.height
                        color: pop.sevColor(SysFmt.severity("mem", pop.stats.mem.usedPct))
                    }
                    Rectangle {
                        width: parent.width * (pop.stats.mem.cachedKB || 0) / parent.parent.total
                        height: parent.height
                        color: Qt.rgba(pop.theme.textSecondary.r, pop.theme.textSecondary.g,
                                       pop.theme.textSecondary.b, 0.4)
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: "used " + SysFmt.fmtKB(pop.stats.mem.usedKB || 0)
                    + "    cached " + SysFmt.fmtKB(pop.stats.mem.cachedKB || 0)
                    + "    free " + SysFmt.fmtKB(pop.stats.mem.freeKB || 0)
                font.family: pop.theme.iconFont; font.pixelSize: 10
                color: pop.theme.textSecondary
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: "swap " + SysFmt.fmtKB(pop.stats.swap.usedKB || 0) + " / "
                        + SysFmt.fmtKB(pop.stats.swap.totalKB || 0)
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.sevColor(SysFmt.severity("swap", pop.stats.swap.pct))
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "pressure  mem " + (pop.stats.psi.mem || 0) + "%"
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.sevColor(SysFmt.severity("psi", pop.stats.psi.mem))
                }
                Text {
                    text: "cpu " + (pop.stats.psi.cpu || 0) + "%"
                    font.family: pop.theme.iconFont; font.pixelSize: 10
                    color: pop.sevColor(SysFmt.severity("psi", pop.stats.psi.cpu))
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: pop.theme.border }

            // --- Two top-process lists side by side ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 2
                    Text {
                        text: "Top memory"
                        font.family: pop.theme.iconFont; font.pixelSize: 11; font.weight: Font.DemiBold
                        color: pop.theme.textSecondary
                    }
                    Repeater {
                        model: pop.stats.topMem
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text {
                                text: modelData.name
                                font.family: pop.theme.iconFont; font.pixelSize: 10
                                color: pop.theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: SysFmt.fmtKB(modelData.rssKB)
                                font.family: pop.theme.iconFont; font.pixelSize: 10
                                color: pop.theme.textSecondary
                            }
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 2
                    Text {
                        text: "Top CPU"
                        font.family: pop.theme.iconFont; font.pixelSize: 11; font.weight: Font.DemiBold
                        color: pop.theme.textSecondary
                    }
                    Repeater {
                        model: pop.stats.topCpu
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text {
                                text: modelData.name
                                font.family: pop.theme.iconFont; font.pixelSize: 10
                                color: pop.theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.pcpu + "%"
                                font.family: pop.theme.iconFont; font.pixelSize: 10
                                color: pop.theme.textSecondary
                            }
                        }
                    }
                }
            }
        }
    }
}
