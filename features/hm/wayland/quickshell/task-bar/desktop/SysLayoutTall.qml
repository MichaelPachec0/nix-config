import QtQuick
import QtQuick.Layouts

// Tall layout: all six sections in a single column with dividers.
// Reproduces the original SysPopup section arrangement verbatim.
ColumnLayout {
    id: root
    spacing: 8

    property QtObject theme
    property var stats
    property var gpu
    property var disk
    property var net

    SysCpuSection  { Layout.fillWidth: true; theme: root.theme; stats: root.stats }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.border }

    SysMemSection  { Layout.fillWidth: true; theme: root.theme; stats: root.stats }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.border; visible: root.gpu.available }

    SysGpuSection  { Layout.fillWidth: true; theme: root.theme; gpu: root.gpu }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.border; visible: root.disk.available }

    SysDiskSection { Layout.fillWidth: true; theme: root.theme; disk: root.disk }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.border; visible: root.net.available }

    SysNetSection  { Layout.fillWidth: true; theme: root.theme; net: root.net }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.border }

    SysProcSection { Layout.fillWidth: true; theme: root.theme; stats: root.stats }
}
