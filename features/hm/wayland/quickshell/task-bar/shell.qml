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
            }

            // The Hub overlay (SUPER+Right-Alt). Hyprland binds that key to a
            // `global, quickshell:hubToggle` dispatch (see hyprland.nix hubBind),
            // which fires this GlobalShortcut.
            Hub.HubWindow {
                id: hub
                screen: v.modelData
                theme: screenTheme
                stats: sysStats
            }

            GlobalShortcut {
                name: "hubToggle"
                description: "Toggle the Quickshell hub"
                onPressed: hub.toggle()
            }
        }
    }
}
