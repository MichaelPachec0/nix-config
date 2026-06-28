// SHELVED 2026-06-24: not instantiated by shell.qml. The rounded frame works
// visually but the wlr-layer-shell reservation/cropping interaction needs rework
// before re-enabling (all-anchored Top-layer surfaces can't reserve; the opaque
// frame painted over windows). Kept for a later look. See spec section 12.4.
import QtQuick
import Quickshell
import Quickshell.Wayland

// Pure decoration: top + side bars + concave corners. Reserves NO space
// (exclusiveZone 0) -- the Taskbar (bottom-anchored) reserves the dock height.
// Top/sides are hidden by the shell when the active workspace has windows, so
// the frame never crops a window; on an empty workspace the full frame shows.
PanelWindow {
    id: win

    required property QtObject theme
    property bool isDarkMode: theme.isDarkMode

    property color frameColor: theme.bgMain

    // Geometry (tuned live for thanatos).
    property int thickness: 7
    property int bottomHeight: 40
    property int radius: 10

    // Driven by the shell: false when the workspace has windows.
    property bool showTopAndSides: true
    property real borderOpacity: showTopAndSides ? 1.0 : 0.0

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    WlrLayershell.layer: WlrLayer.Top
    exclusiveZone: 0
    mask: Region {}
    color: "transparent"

    // Top bar
    Rectangle {
        height: win.thickness
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        color: win.frameColor
        opacity: win.borderOpacity
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutQuart
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
    }
    // Left bar
    Rectangle {
        width: win.thickness
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
        }
        anchors.topMargin: win.thickness
        anchors.bottomMargin: win.bottomHeight
        color: win.frameColor
        opacity: win.borderOpacity
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutQuart
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
    }
    // Right bar
    Rectangle {
        width: win.thickness
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
        }
        anchors.topMargin: win.thickness
        anchors.bottomMargin: win.bottomHeight
        color: win.frameColor
        opacity: win.borderOpacity
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutQuart
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
    }

    // Inverted (concave) corners -- one Canvas each, hidden with the top/sides.
    component Corner: Canvas {
        property string kind: "TL"
        width: win.radius
        height: win.radius
        opacity: win.borderOpacity
        visible: opacity > 0
        property color c: win.frameColor
        onCChanged: requestPaint()
        onPaint: win.drawInvertedCorner(getContext("2d"), width, height, kind)
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutQuart
            }
        }
    }
    Corner {
        kind: "TL"
        anchors {
            top: parent.top
            left: parent.left
        }
        anchors.topMargin: win.thickness
        anchors.leftMargin: win.thickness
    }
    Corner {
        kind: "TR"
        anchors {
            top: parent.top
            right: parent.right
        }
        anchors.topMargin: win.thickness
        anchors.rightMargin: win.thickness
    }
    Corner {
        kind: "BL"
        anchors {
            bottom: parent.bottom
            left: parent.left
        }
        anchors.bottomMargin: win.bottomHeight
        anchors.leftMargin: win.thickness
    }
    Corner {
        kind: "BR"
        anchors {
            bottom: parent.bottom
            right: parent.right
        }
        anchors.bottomMargin: win.bottomHeight
        anchors.rightMargin: win.thickness
    }

    function drawInvertedCorner(ctx, w, h, type) {
        ctx.reset();
        ctx.fillStyle = win.frameColor;
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(w, 0);
        ctx.lineTo(w, h);
        ctx.lineTo(0, h);
        ctx.closePath();
        if (type === "TL") {
            ctx.globalCompositeOperation = "source-over";
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(w, 0);
            ctx.arc(w, h, w, 1.5 * Math.PI, Math.PI, true);
            ctx.lineTo(0, 0);
            ctx.fill();
        } else if (type === "TR") {
            ctx.beginPath();
            ctx.moveTo(w, 0);
            ctx.lineTo(w, h);
            ctx.arc(0, h, w, 0, 1.5 * Math.PI, true);
            ctx.lineTo(w, 0);
            ctx.fill();
        } else if (type === "BL") {
            ctx.beginPath();
            ctx.moveTo(0, h);
            ctx.lineTo(0, 0);
            ctx.arc(w, 0, w, Math.PI, 0.5 * Math.PI, true);
            ctx.lineTo(0, h);
            ctx.fill();
        } else if (type === "BR") {
            ctx.beginPath();
            ctx.moveTo(w, h);
            ctx.lineTo(0, h);
            ctx.arc(0, 0, w, 0.5 * Math.PI, 0, true);
            ctx.lineTo(w, h);
            ctx.fill();
        }
    }
}
