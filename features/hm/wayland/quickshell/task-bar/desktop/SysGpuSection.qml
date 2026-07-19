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

    // Reserved widths: GPU% and temperature reserve their max string so a growing
    // digit never reflows the row; the VRAM field is the flexible absorber below.
    readonly property real _wPct: _mPct.advanceWidth
    readonly property real _wTemp: _mTemp.advanceWidth
    TextMetrics { id: _mPct;  font.family: root.theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold; text: "GPU 100%" }
    TextMetrics { id: _mTemp; font.family: root.theme.iconFont; font.pixelSize: 11; text: "100 C" }

    // Header: GPU util%, VRAM, temperature. VRAM elides under pressure so the
    // right-aligned temperature stays inside the column instead of overflowing.
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Text {
            text: "GPU " + Math.round(root.gpu.util) + "%"
            font.family: root.theme.iconFont; font.pixelSize: 12; font.weight: Font.DemiBold
            color: SysFmt.sevColor(root.theme,SysFmt.severity("cpu", root.gpu.util))
            Layout.minimumWidth: root._wPct
        }
        Text {
            text: "VRAM " + SysFmt.fmtKB(root.gpu.vramUsed / 1024) + " / "
                + SysFmt.fmtKB(root.gpu.vramTotal / 1024)
            font.family: root.theme.iconFont; font.pixelSize: 11
            color: root.theme.textSecondary
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            text: Math.round(root.gpu.temp) + " C"
            font.family: root.theme.iconFont; font.pixelSize: 11
            color: SysFmt.sevColor(root.theme,SysFmt.severity("temp", root.gpu.temp))
            horizontalAlignment: Text.AlignRight
            Layout.minimumWidth: root._wTemp
            Layout.preferredWidth: root._wTemp
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
