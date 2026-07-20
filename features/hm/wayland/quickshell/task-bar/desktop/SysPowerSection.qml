import QtQuick
import QtQuick.Layouts
import "../lib/sysfmt.js" as SysFmt

// Power/SMU section: PPT/STAPM/TDC/EDC utilisation bars plus FCLK/MCLK/GFX
// for AMD APUs. Hidden when the smu provider reports unavailable.
ColumnLayout {
    id: root
    spacing: 4
    // Guard against smu being momentarily undefined during construction (it is
    // fed by the parent layout's binding, so it is not `required` here).
    visible: !!root.smu && root.smu.available

    required property QtObject theme
    property var smu

    Text {
        text: "Power"
        font.family: root.theme.iconFont
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: root.theme.textSecondary
    }

    // PPT/STAPM/TDC/EDC utilisation rows. STAPM is APU-only (hidden when absent).
    PowerBar { theme: root.theme; label: "PPT";   value: root.smu.ppt;   limit: root.smu.pptLimit;   unit: "W" }
    PowerBar { theme: root.theme; label: "STAPM"; value: root.smu.stapm; limit: root.smu.stapmLimit; unit: "W"; visible: root.smu.stapmLimit > 0 }
    PowerBar { theme: root.theme; label: "TDC";   value: root.smu.tdc;   limit: root.smu.tdcLimit;   unit: "A" }
    PowerBar { theme: root.theme; label: "EDC";   value: root.smu.edc;   limit: root.smu.edcLimit;   unit: "A" }

    // Clocks and GFX busy summary line
    Text {
        Layout.fillWidth: true
        // gfx_busy is garbage on some APUs (double-scaled to >100%); only show it
        // when sane. Real GPU usage is already in the GPU section (amdgpu sysfs).
        text: "FCLK " + Math.round(root.smu.fclk) + "  MCLK " + Math.round(root.smu.mclk)
            + (root.smu.gfxBusy >= 0 && root.smu.gfxBusy <= 100
               ? "  GFX " + Math.round(root.smu.gfxBusy) + "%" : "")
        font.family: root.theme.iconFont
        font.pixelSize: 10
        color: root.theme.textSecondary
        elide: Text.ElideRight
    }
}
