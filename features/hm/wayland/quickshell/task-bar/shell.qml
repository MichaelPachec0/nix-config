//@ pragma UseQApplication
// QApplication mode is required for native platform menus (SystemTrayItem.display),
// which we use for tray items whose menus don't play well with our themed popup --
// nm-applet (rebuilds on every Wi-Fi scan) and Electron/Chromium apps (menu only
// populates for a native client). See desktop/Taskbar.qml tray dispatch.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import "lib" as Lib
import "desktop" as Desktop
import "hub" as Hub

ShellRoot {
    // Global notification service (one server for all screens).
    Lib.NotifService {
        id: notifSvc
    }

    // Global Bluetooth state (one default adapter, shared by all screens).
    Lib.BluetoothService {
        id: btSvc
    }

    // Global audio state (native PipeWire), shared by the bar widget surfaces.
    Lib.AudioService {
        id: audioSvc
    }

    // Shared, disk-persisted calendar layout choice (one instance for all
    // monitors; passed into every Taskbar).
    Lib.CalState {
        id: calState
    }

    // Mirror Hyprland's screencast state into the notification service so toasts
    // are suppressed while screen sharing -- the QS-native replacement for the
    // swaync screencast inhibitor (see quickshell-notifications-cutover). The
    // `screencast` IPC event carries `state,owner`; state 1 = sharing, 0 = off.
    // If qs restarts mid-cast it misses the opening event, but the next state
    // change re-syncs (rare, and only costs a few un-suppressed toasts).
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "screencast")
                notifSvc.screencasting = event.parse(2)[0] === "1";
        }
    }

    Variants {
        model: Quickshell.screens
        Scope {
            id: v
            property var modelData

            Lib.ThemeEngine {
                id: screenTheme
            }

            // Shared CPU/RAM poller, read by the bar and the hub header.
            Lib.SysStats {
                id: sysStats
            }

            // Shared weather location selection (bar widget <-> hub card chips).
            QtObject {
                id: weatherState
                property string selectedId: "geo"
            }

            // NOTE (shelved 2026-06-24): the rounded ScreenBorder is set aside.
            // Its wlr-layer-shell space-reservation + top/side cropping needs
            // rework before re-enabling (an all-anchored Top-layer surface can't
            // reserve, and the opaque frame paints over windows). The component
            // is kept in desktop/ScreenBorder.qml; to restore, instantiate it
            // here with `theme: screenTheme; showTopAndSides: !taskbar.hasWindows`.
            // See spec section 12.4 (Shelved).

            Desktop.Taskbar {
                id: taskbar
                screen: v.modelData
                theme: screenTheme
                stats: sysStats
                weatherState: weatherState
                bt: btSvc
                audio: audioSvc
                calState: calState
            }

            // The Hub overlay (SUPER+Right-Alt). Hyprland binds that key to a
            // `global, quickshell:hubToggle` dispatch (see hyprland.nix hubBind),
            // which fires this GlobalShortcut.
            Hub.HubWindow {
                id: hub
                screen: v.modelData
                theme: screenTheme
                stats: sysStats
                weatherState: weatherState
                notif: notifSvc
            }

            // Toast popups (top-right, below the bar).
            Desktop.ToastOverlay {
                screen: v.modelData
                theme: screenTheme
                notif: notifSvc
            }

            GlobalShortcut {
                name: "hubToggle"
                description: "Toggle the hub (settings + notifications)"
                onPressed: hub.hubToggle()
            }

            GlobalShortcut {
                name: "notifToggle"
                description: "Toggle the notifications panel only"
                onPressed: hub.notifToggle()
            }

        }
    }
}
