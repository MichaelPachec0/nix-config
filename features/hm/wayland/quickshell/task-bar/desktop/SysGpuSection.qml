import QtQuick
import QtQuick.Layouts
import "../lib" as Lib
import "../lib/sysfmt.js" as SysFmt

// GPU section: hidden when gpu.available is false (no GPU detected).
// Header row: util%, VRAM used/total, temp. Then history sparkline.
// VRAM props on GpuStats are bytes; divide by 1024 before fmtKB (expects KB).
ColumnLayout {
    id: root
    spacing: 6
    visible: root.gpu.available

    required property QtObject theme
    required property var gpu

    function sevColor(sev) {
        return sev === "good" ? theme.accentGreen
             : sev === "fair" ? theme.accentYellow : theme.accentRed;
    }

    // Header: GPU util%, VRAM, temperature
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Text {
            text: "GPU " + Math.round(root.gpu.util) + "%"
            font.family: root.theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold
            color: root.sevColor(SysFmt.severity("cpu", root.gpu.util))
        }
        Text {
            text: "VRAM " + SysFmt.fmtKB(root.gpu.vramUsed / 1024) + " / "
                + SysFmt.fmtKB(root.gpu.vramTotal / 1024)
            font.family: root.theme.iconFont; font.pixelSize: 11
            color: root.theme.textSecondary
        }
        Item { Layout.fillWidth: true }
        Text {
            text: Math.round(root.gpu.temp) + " C"
            font.family: root.theme.iconFont; font.pixelSize: 11
            color: root.sevColor(SysFmt.severity("temp", root.gpu.temp))
        }
    }

    // History sparklines: GPU usage (accent) + VRAM used % (blue).
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
            text: "usage"
            color: root.theme.textSecondary
            font.family: root.theme.iconFont
            font.pixelSize: 9
        }
        Lib.Sparkline {
            Layout.fillWidth: true
            implicitHeight: 22
            values: root.gpu.gpuHist
            color: root.theme.accent
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
            text: "vram"
            color: root.theme.textSecondary
            font.family: root.theme.iconFont
            font.pixelSize: 9
        }
        Lib.Sparkline {
            Layout.fillWidth: true
            implicitHeight: 22
            values: root.gpu.vramHist
            color: root.theme.accentBlue
        }
    }
}
