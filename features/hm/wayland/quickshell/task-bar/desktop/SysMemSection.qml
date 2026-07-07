import QtQuick
import QtQuick.Layouts
import "../lib" as Lib
import "../lib/sysfmt.js" as SysFmt

// Memory section: header, segmented used|cached|free bar, detail line,
// swap/PSI row, history sparkline. Consumed by the SysPopup composition layer.
ColumnLayout {
    id: root
    spacing: 6

    required property QtObject theme
    required property var stats

    function sevColor(sev) {
        return sev === "good" ? theme.accentGreen
             : sev === "fair" ? theme.accentYellow : theme.accentRed;
    }

    // Reserved widths for the PSI figures so a 1->2->3 digit percent keeps the
    // mem/cpu columns aligned. Swap and pressure live on their own rows below.
    readonly property real _wPsiMem: _mPsiMem.advanceWidth
    readonly property real _wPsiCpu: _mPsiCpu.advanceWidth
    TextMetrics { id: _mPsiMem; font.family: root.theme.iconFont; font.pixelSize: 10; text: "mem 100%" }
    TextMetrics { id: _mPsiCpu; font.family: root.theme.iconFont; font.pixelSize: 10; text: "cpu 100%" }

    // Header: used / total (pct%)
    RowLayout {
        Layout.fillWidth: true
        Text {
            text: "Memory  " + SysFmt.fmtKB(root.stats.mem.usedKB || 0) + " / "
                + SysFmt.fmtKB(root.stats.mem.totalKB || 0) + "  (" + (root.stats.mem.usedPct || 0) + "%)"
            font.family: root.theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold
            color: root.sevColor(SysFmt.severity("mem", root.stats.mem.usedPct))
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    // Segmented bar: used | cached | free
    Rectangle {
        Layout.fillWidth: true
        height: 10
        radius: 3
        color: Qt.rgba(root.theme.textSecondary.r, root.theme.textSecondary.g,
                       root.theme.textSecondary.b, 0.15)
        readonly property real total: (root.stats.mem.totalKB || 1)
        Row {
            anchors.fill: parent
            Rectangle {
                width: parent.width * (root.stats.mem.usedKB || 0) / parent.parent.total
                height: parent.height
                color: root.sevColor(SysFmt.severity("mem", root.stats.mem.usedPct))
            }
            Rectangle {
                width: parent.width * (root.stats.mem.cachedKB || 0) / parent.parent.total
                height: parent.height
                color: Qt.rgba(root.theme.textSecondary.r, root.theme.textSecondary.g,
                               root.theme.textSecondary.b, 0.4)
            }
        }
    }

    // Used / cached / free detail line
    Text {
        Layout.fillWidth: true
        text: "used " + SysFmt.fmtKB(root.stats.mem.usedKB || 0)
            + "    cached " + SysFmt.fmtKB(root.stats.mem.cachedKB || 0)
            + "    free " + SysFmt.fmtKB(root.stats.mem.freeKB || 0)
        font.family: root.theme.iconFont; font.pixelSize: 10
        color: root.theme.textSecondary
        elide: Text.ElideRight
    }

    // Swap row (own line)
    Text {
        Layout.fillWidth: true
        text: "swap " + SysFmt.fmtKB(root.stats.swap.usedKB || 0) + " / "
            + SysFmt.fmtKB(root.stats.swap.totalKB || 0)
        font.family: root.theme.iconFont; font.pixelSize: 10
        color: root.sevColor(SysFmt.severity("swap", root.stats.swap.pct))
        elide: Text.ElideRight
    }

    // Pressure row (own line so it can never collide with swap). mem/cpu reserve
    // their width so the cpu figure stays put when mem crosses a digit.
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Text {
            text: "pressure"
            font.family: root.theme.iconFont; font.pixelSize: 10
            color: root.theme.textSecondary
        }
        Text {
            text: "mem " + (root.stats.psi.mem || 0) + "%"
            font.family: root.theme.iconFont; font.pixelSize: 10
            color: root.sevColor(SysFmt.severity("psi", root.stats.psi.mem))
            Layout.minimumWidth: root._wPsiMem
            Layout.preferredWidth: root._wPsiMem
        }
        Text {
            text: "cpu " + (root.stats.psi.cpu || 0) + "%"
            font.family: root.theme.iconFont; font.pixelSize: 10
            color: root.sevColor(SysFmt.severity("psi", root.stats.psi.cpu))
            Layout.minimumWidth: root._wPsiCpu
            Layout.preferredWidth: root._wPsiCpu
        }
        Item { Layout.fillWidth: true }
    }

    // History sparkline
    Lib.Sparkline {
        Layout.fillWidth: true
        implicitHeight: 22
        values: root.stats.ramHist
        color: root.theme.accent
    }
}
