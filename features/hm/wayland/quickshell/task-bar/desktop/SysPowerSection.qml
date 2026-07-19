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

    // PPT row
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
            text: "PPT"
            font.family: root.theme.iconFont
            font.pixelSize: 10
            color: root.theme.textPrimary
            Layout.preferredWidth: 40
        }
        Text {
            text: Math.round(root.smu.ppt) + " / " + Math.round(root.smu.pptLimit) + " W"
            font.family: root.theme.iconFont
            font.pixelSize: 10
            color: SysFmt.sevColor(root.theme,SysFmt.severity("cpu", pptBar.fraction * 100))
            Layout.fillWidth: true
        }
        Rectangle {
            id: pptBar
            implicitWidth: 70
            implicitHeight: 6
            radius: 2
            color: root.theme.subtleFill
            readonly property real fraction: root.smu.pptLimit > 0
                ? Math.min(1, Math.max(0, root.smu.ppt / root.smu.pptLimit)) : 0
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * parent.fraction
                radius: parent.radius
                color: SysFmt.sevColor(root.theme,SysFmt.severity("cpu", parent.fraction * 100))
            }
        }
    }

    // STAPM row (APU sustained limit; absent on non-APU parts)
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: root.smu.stapmLimit > 0
        Text {
            text: "STAPM"
            font.family: root.theme.iconFont
            font.pixelSize: 10
            color: root.theme.textPrimary
            Layout.preferredWidth: 40
        }
        Text {
            text: Math.round(root.smu.stapm) + " / " + Math.round(root.smu.stapmLimit) + " W"
            font.family: root.theme.iconFont
            font.pixelSize: 10
            color: SysFmt.sevColor(root.theme,SysFmt.severity("cpu", stapmBar.fraction * 100))
            Layout.fillWidth: true
        }
        Rectangle {
            id: stapmBar
            implicitWidth: 70
            implicitHeight: 6
            radius: 2
            color: root.theme.subtleFill
            readonly property real fraction: root.smu.stapmLimit > 0
                ? Math.min(1, Math.max(0, root.smu.stapm / root.smu.stapmLimit)) : 0
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * parent.fraction
                radius: parent.radius
                color: SysFmt.sevColor(root.theme,SysFmt.severity("cpu", parent.fraction * 100))
            }
        }
    }

    // TDC row
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
            text: "TDC"
            font.family: root.theme.iconFont
            font.pixelSize: 10
            color: root.theme.textPrimary
            Layout.preferredWidth: 40
        }
        Text {
            text: Math.round(root.smu.tdc) + " / " + Math.round(root.smu.tdcLimit) + " A"
            font.family: root.theme.iconFont
            font.pixelSize: 10
            color: SysFmt.sevColor(root.theme,SysFmt.severity("cpu", tdcBar.fraction * 100))
            Layout.fillWidth: true
        }
        Rectangle {
            id: tdcBar
            implicitWidth: 70
            implicitHeight: 6
            radius: 2
            color: root.theme.subtleFill
            readonly property real fraction: root.smu.tdcLimit > 0
                ? Math.min(1, Math.max(0, root.smu.tdc / root.smu.tdcLimit)) : 0
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * parent.fraction
                radius: parent.radius
                color: SysFmt.sevColor(root.theme,SysFmt.severity("cpu", parent.fraction * 100))
            }
        }
    }

    // EDC row
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
            text: "EDC"
            font.family: root.theme.iconFont
            font.pixelSize: 10
            color: root.theme.textPrimary
            Layout.preferredWidth: 40
        }
        Text {
            text: Math.round(root.smu.edc) + " / " + Math.round(root.smu.edcLimit) + " A"
            font.family: root.theme.iconFont
            font.pixelSize: 10
            color: SysFmt.sevColor(root.theme,SysFmt.severity("cpu", edcBar.fraction * 100))
            Layout.fillWidth: true
        }
        Rectangle {
            id: edcBar
            implicitWidth: 70
            implicitHeight: 6
            radius: 2
            color: root.theme.subtleFill
            readonly property real fraction: root.smu.edcLimit > 0
                ? Math.min(1, Math.max(0, root.smu.edc / root.smu.edcLimit)) : 0
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * parent.fraction
                radius: parent.radius
                color: SysFmt.sevColor(root.theme,SysFmt.severity("cpu", parent.fraction * 100))
            }
        }
    }

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
