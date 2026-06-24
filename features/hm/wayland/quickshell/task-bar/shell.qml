import Quickshell
import QtQuick
import "lib" as Lib
import "desktop" as Desktop

ShellRoot {
    Variants {
        model: Quickshell.screens
        Scope {
            id: v
            property var modelData

            Lib.ThemeEngine {
                id: screenTheme
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
            }
        }
    }
}
