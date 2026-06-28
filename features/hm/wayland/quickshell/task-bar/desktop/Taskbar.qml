import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts

// Top bar (waybar-style). Top-anchored so it RESERVES its height (windows sit
// below it). Draws the bar background + workspace chips + per-window app icons.
// `hasWindows` is kept for the shelved screen-border's auto-hide.
PanelWindow {
    id: dock

    required property QtObject theme
    property QtObject stats: null
    property QtObject weatherState: null
    property QtObject bt: null
    property QtObject audio: null

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 40
    color: dock.theme.bgMain
    WlrLayershell.layer: WlrLayer.Top

    readonly property int activeWs: Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1

    // Reactive: true when any toplevel is on the active workspace.
    readonly property bool hasWindows: {
        var list = Hyprland.toplevels?.values ?? [];
        for (var i = 0; i < list.length; i++)
            if ((list[i].workspace?.id ?? -2) === dock.activeWs)
                return true;
        return false;
    }

    // Map a Hyprland window class to a themed icon path. A few classes don't
    // match a desktop entry / icon name (firefox-dev, the hy3proj terminal);
    // override those, else use the desktop-entry heuristic, else the raw class.
    function iconFor(cls) {
        var raw = cls || "";
        // No class yet (a toplevel paints one frame before its lastIpcObject
        // arrives) -> render nothing rather than flashing the generic cog.
        if (raw.length === 0)
            return "";
        var c = raw.toLowerCase();
        var name = "";
        // Explicit class->icon overrides for classes that don't equal their icon
        // name. heuristicLookup is unreliable here, so we don't depend on it.
        if (c.indexOf("firefox") >= 0)
            name = "firefox-devedition";
        else if (c === "hy3proj")
            name = "kitty";
        else if (c === "signal")
            name = "signal-desktop";
        else if (c.indexOf("keepassxc") >= 0)
            name = "keepassxc";
        else if (raw.length > 0) {
            // Try the desktop-entry heuristic (original case), else the raw class
            // (works when class == icon name, e.g. kitty, org.telegram.desktop).
            var entry = DesktopEntries.heuristicLookup(raw);
            name = (entry && entry.icon) ? entry.icon : raw;
        }
        if (name.length === 0)
            name = "application-x-executable";
        return Quickshell.iconPath(name, "application-x-executable");
    }

    // --- Clock helpers (12/24h toggle + UTC/NYC) ---
    property bool h12: false
    property bool tick: false // toggled every second; bindings read it to re-eval
    property int dateFmt: 0 // 0=Wed, Jun 24 2026  1=06-24-2026  2=2026-06-24

    function localTime() {
        var d = new Date();
        return dock.h12 ? Qt.formatDateTime(d, "h:mm AP") : Qt.formatDateTime(d, "HH:mm");
    }
    function dateStr() {
        var d = new Date();
        if (dock.dateFmt === 1)
            return Qt.formatDateTime(d, "MM-dd-yyyy");
        if (dock.dateFmt === 2)
            return Qt.formatDateTime(d, "yyyy-MM-dd");
        return Qt.formatDateTime(d, "ddd, MMM d yyyy");
    }
    function fmtHM(h, m) {
        var mm = (m < 10 ? "0" : "") + m;
        if (dock.h12) {
            var ap = h >= 12 ? "PM" : "AM";
            var hh = h % 12;
            if (hh === 0)
                hh = 12;
            return hh + ":" + mm + " " + ap;
        }
        return (h < 10 ? "0" : "") + h + ":" + mm;
    }
    // US DST: 2nd Sun Mar .. 1st Sun Nov (boundary approximated at 07:00 UTC).
    function nycIsDst(d) {
        var y = d.getUTCFullYear();
        function nthSun(month, n) {
            var first = new Date(Date.UTC(y, month, 1, 7, 0, 0));
            var firstSun = 1 + ((7 - first.getUTCDay()) % 7);
            return Date.UTC(y, month, firstSun + (n - 1) * 7, 7, 0, 0);
        }
        var t = d.getTime();
        return t >= nthSun(2, 2) && t < nthSun(10, 1);
    }
    function tzTime(tz) {
        var d = new Date();
        if (tz === "UTC")
            return dock.fmtHM(d.getUTCHours(), d.getUTCMinutes());
        // NYC (America/New_York): EDT (UTC-4) in summer, EST (UTC-5) otherwise.
        var off = dock.nycIsDst(d) ? -4 : -5;
        var h = ((d.getUTCHours() + off) % 24 + 24) % 24;
        return dock.fmtHM(h, d.getUTCMinutes());
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: dock.tick = !dock.tick
    }

    // Shared themed context menu for tray items (opened on right-click).
    TrayMenu {
        id: trayMenu
        theme: dock.theme
    }

    // Left: workspaces + window icons
    RowLayout {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Repeater {
            model: Hyprland.workspaces
            Rectangle {
                id: ws
                required property var modelData
                readonly property bool active: modelData.id === dock.activeWs
                implicitWidth: active ? 34 : 26
                implicitHeight: 22
                radius: 11
                color: active ? dock.theme.accent : dock.theme.bgItem
                Behavior on implicitWidth {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutBack
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: ws.modelData.id
                    color: ws.active ? dock.theme.textOnAccent : dock.theme.textSecondary
                    font.family: dock.theme.textFont
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + ws.modelData.id + " })")
                }
            }
        }

        // Divider (only when the active workspace has windows)
        Rectangle {
            visible: dock.hasWindows
            Layout.preferredWidth: 1
            Layout.preferredHeight: 18
            color: dock.theme.border
        }

        // Windows on the active workspace -- real app icons, click to focus.
        Repeater {
            model: Hyprland.toplevels
            MouseArea {
                id: win
                required property var modelData
                readonly property bool onActive: (modelData.workspace?.id ?? -2) === dock.activeWs
                readonly property bool isActive: modelData === Hyprland.activeToplevel
                readonly property string cls: modelData.lastIpcObject?.class ?? ""
                readonly property string addr: {
                    var a = (modelData.address && modelData.address.length > 0) ? modelData.address : (modelData.lastIpcObject?.address ?? "");
                    return (a.indexOf("0x") === 0) ? a : ("0x" + a);
                }
                visible: onActive
                implicitWidth: 36
                implicitHeight: 32
                onClicked: Hyprland.dispatch('hl.dsp.focus({ window = "address:' + win.addr + '" })')

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: win.isActive ? dock.theme.bgItemHover : "transparent"

                    Image {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        sourceSize.width: 40
                        sourceSize.height: 40
                        source: dock.iconFor(win.cls)
                    }
                    Rectangle {
                        visible: win.isActive
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 16
                        height: 2
                        radius: 1
                        color: dock.theme.accent
                    }
                }
            }
        }
    }

    // Right: status widgets (media, CPU/RAM, tray, battery, weather, date, clock).
    RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        // MPRIS now-playing: play/pause + marquee title (only while a player runs).
        // Hover reveals a full-player popup with seek.
        MediaWidget {
            Layout.alignment: Qt.AlignVCenter
            theme: dock.theme
            barWindow: dock
        }

        // Audio (native PipeWire): volume glyph + %, click for the mixer.
        AudioWidget {
            Layout.alignment: Qt.AlignVCenter
            theme: dock.theme
            barWindow: dock
            audio: dock.audio
        }

        // WiFi (native nm-applet replacement): signal glyph + SSID, click for menu.
        NetworkWidget {
            Layout.alignment: Qt.AlignVCenter
            theme: dock.theme
            barWindow: dock
        }

        // Bluetooth: state glyph + connected device, click for the device menu.
        BluetoothWidget {
            Layout.alignment: Qt.AlignVCenter
            theme: dock.theme
            barWindow: dock
            bt: dock.bt
        }

        // CPU / RAM (shared SysStats): microchip + memory glyph, then percent.
        RowLayout {
            spacing: 10
            visible: dock.stats !== null

            RowLayout {
                spacing: 4
                Text {
                    text: String.fromCharCode(0xF2DB) // microchip
                    color: dock.theme.textSecondary
                    font.family: dock.theme.faFont
                    font.pixelSize: 10
                }
                Text {
                    text: Math.round(dock.stats ? dock.stats.cpuPct : 0) + "%"
                    color: dock.theme.textSecondary
                    font.family: dock.theme.textFont
                    font.pixelSize: 11
                }
            }
            RowLayout {
                spacing: 4
                Text {
                    text: String.fromCharCode(0xF538) // memory
                    color: dock.theme.textSecondary
                    font.family: dock.theme.faFont
                    font.pixelSize: 10
                }
                Text {
                    text: Math.round(dock.stats ? dock.stats.ramPct : 0) + "%"
                    color: dock.theme.textSecondary
                    font.family: dock.theme.textFont
                    font.pixelSize: 11
                }
            }
        }

        // System tray (StatusNotifier items): left-click activate, middle-click
        // secondary, right-click opens the item's DBus context menu. Items that
        // are menu-only (no activate action) open their menu on left-click too.
        RowLayout {
            spacing: 8
            visible: SystemTray.items.values.length > 0

            Repeater {
                model: SystemTray.items
                MouseArea {
                    id: trayItem
                    required property var modelData
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 20
                    implicitHeight: 20
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: function (mouse) {
                        var item = trayItem.modelData;
                        var wantMenu = mouse.button === Qt.RightButton || (mouse.button === Qt.LeftButton && item.onlyMenu);
                        if (wantMenu) {
                            if (item.hasMenu) {
                                // nm-applet rebuilds its menu on every Wi-Fi scan,
                                // which thrashes the QML drill-down, so it uses the
                                // native menu. Everything else uses the themed popup.
                                // We deliberately do NOT route Chromium/Electron apps
                                // to native: Quickshell segfaults in PlatformMenuEntry
                                // teardown when a canonical-dbusmenu item whose native
                                // menu was opened later unregisters (reproduced on
                                // several Electron apps' exit). nm-applet uses the
                                // ayatana menu backend and a persistent process, so it
                                // doesn't hit that path.
                                var id = (item.id || "").toLowerCase();
                                var native = id.indexOf("nm-applet") >= 0;
                                if (native) {
                                    var pl = trayItem.mapToItem(null, 0, trayItem.height + 4);
                                    item.display(dock, pl.x, pl.y);
                                } else {
                                    // Themed menu, right-aligned under the icon.
                                    var p = trayItem.mapToItem(null, trayItem.width, trayItem.height + 4);
                                    trayMenu.openAt(dock, p.x, p.y, item.menu);
                                }
                            }
                        } else if (mouse.button === Qt.MiddleButton) {
                            item.secondaryActivate();
                        } else {
                            item.activate();
                        }
                    }
                    Image {
                        anchors.fill: parent
                        sourceSize.width: 40
                        sourceSize.height: 40
                        fillMode: Image.PreserveAspectFit
                        source: trayItem.modelData.icon
                    }
                }
            }
        }

        // Keep-awake: toggle a Wayland idle inhibitor (blocks idle lock / DPMS).
        InhibitWidget {
            Layout.alignment: Qt.AlignVCenter
            theme: dock.theme
            barWindow: dock
        }

        // Battery (laptop only): drawn battery + charging bolt; hover for details.
        BatteryWidget {
            Layout.alignment: Qt.AlignVCenter
            theme: dock.theme
            barWindow: dock
        }

        // Weather: current condition glyph + temperature; hover for details.
        WeatherWidget {
            Layout.alignment: Qt.AlignVCenter
            theme: dock.theme
            barWindow: dock
            weatherState: dock.weatherState
        }

        Text {
            id: dateText
            color: dock.theme.textSecondary
            font.family: dock.theme.textFont
            font.pixelSize: 13
            text: {
                dock.tick; // ride the clock's tick (updates at midnight)
                return dock.dateStr();
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: dock.dateFmt = (dock.dateFmt + 1) % 3
            }
        }
        Text {
            id: clockText
            color: dock.theme.textPrimary
            font.family: dock.theme.textFont
            font.pixelSize: 13
            text: {
                dock.tick; // re-evaluate every second
                if (clockMouse.containsMouse)
                    return "UTC " + dock.tzTime("UTC") + "   NYC " + dock.tzTime("NYC");
                return dock.localTime();
            }
            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: dock.h12 = !dock.h12
            }
        }
    }
}
