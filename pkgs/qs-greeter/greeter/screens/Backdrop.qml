import QtQuick
import Quickshell
import Quickshell.Wayland

// Background layer, one per output. Core-owned rather than skin-owned so a
// broken skin still leaves a sane screen behind the fallback.
PanelWindow {
    id: root
    required property var modelData

    screen: modelData
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "qs-greeter:backdrop"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: (Settings.config.backdrop && Settings.config.backdrop.color) || "#3A6EA5"
    }

    Image {
        anchors.fill: parent
        visible: Settings.backdropPath !== "" && status === Image.Ready
        source: Settings.backdropPath !== "" ? "file://" + Settings.backdropPath : ""
        fillMode: {
            var fit = (Settings.config.backdrop && Settings.config.backdrop.fit) || "cover";
            if (fit === "contain") return Image.PreserveAspectFit;
            if (fit === "fill") return Image.Stretch;
            if (fit === "tile") return Image.Tile;
            return Image.PreserveAspectCrop;
        }
        asynchronous: true
        onStatusChanged: if (status === Image.Error)
            Log.warn("backdrop image failed to load: " + Settings.backdropPath);
    }
}
