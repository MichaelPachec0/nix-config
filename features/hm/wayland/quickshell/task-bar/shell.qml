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
    id: shellRoot

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

    // Global Hyprland submap state (compositor-wide), shared by all screens.
    // NB: this id (submapSvc) must differ from the name of the Taskbar property
    // it feeds (submap), matching btSvc->bt / audioSvc->audio. A binding whose
    // right-hand side matches the target property name (submapSvc: submapSvc)
    // resolves to the Taskbar's own property (null), because an object's own
    // property shadows an enclosing-component id in QML scope resolution -- so
    // the pill would silently never receive the service.
    Lib.HyprSubmapService {
        id: submapSvc
    }

    // Global network state: one NetworkManager status poll for all screens
    // (previously each NetworkWidget spawned its own ~20-process nmcli poll every
    // 4s, multiplied by the monitor count). Named netSvc (not `net`) to differ
    // from the Taskbar `net` property it feeds -- see the submapSvc note above.
    Lib.NetworkService {
        id: netSvc
    }

    // Global keep-awake state: one logind sleep inhibitor + one state-file writer
    // for all screens. Per-monitor instances each held their own inhibitor and,
    // with watchChanges off, diverged on toggle. Window-free -- the per-screen
    // Wayland IdleInhibitor stays in AwakeCluster.
    Lib.InhibitService {
        id: inhibitSvc
    }

    // GL-E5800 router status (reads the hardened poll service's
    // /run/e5800/status.json). One reader for all screens. The id MUST differ
    // from the Taskbar `routerSvc` property it feeds: a same-name binding
    // (routerSvc: routerSvc) across the Variants delegate resolves to the
    // Taskbar's own null property (own-property shadows the outer-component id),
    // so the router widget would get svc=null. Matches btSvc->bt / netSvc->net.
    Lib.RouterService {
        id: e5800Svc
    }

    // Shared CPU/RAM poller, read by every bar + hub header. One /proc reader for
    // all screens (was one per monitor).
    Lib.SysStats {
        id: sysStats
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

    // Per-screen HubWindows register themselves here (below) so the two global
    // shortcuts can toggle the hub on the FOCUSED monitor. Previously each screen
    // declared its own hubToggle/notifToggle GlobalShortcut inside the Variants
    // delegate, registering the same shortcut name once per monitor.
    property var hubsByMonitor: ({})
    function focusedHub() {
        var reg = shellRoot.hubsByMonitor;
        for (var k in reg) {
            var h = reg[k];
            var m = (h && h.screen) ? Hyprland.monitorFor(h.screen) : null;
            if (m && m.focused)
                return h;
        }
        return null;
    }

    GlobalShortcut {
        name: "hubToggle"
        description: "Toggle the hub (settings + notifications) on the focused monitor"
        onPressed: {
            var h = shellRoot.focusedHub();
            if (h)
                h.hubToggle();
        }
    }
    GlobalShortcut {
        name: "notifToggle"
        description: "Toggle the notifications panel on the focused monitor"
        onPressed: {
            var h = shellRoot.focusedHub();
            if (h)
                h.notifToggle();
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

            // Disk-persisted calendar layout choice. Kept per-screen by choice so
            // each monitor can hold its own layout; the instances read/write the
            // same state file and FileView watchChanges keeps them in sync. (A
            // single ShellRoot instance would also resolve fine -- see the shared
            // services above -- this is a UX choice, not a resolution limit.)
            Lib.CalState {
                id: calState
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
                submap: submapSvc
                calState: calState
                routerSvc: e5800Svc
                net: netSvc
                inhibit: inhibitSvc
            }

            // The Hub overlay (SUPER+Right-Alt). Hyprland binds that key to a
            // `global, quickshell:hubToggle` dispatch (see hyprland.nix hubBind),
            // which fires the single ShellRoot GlobalShortcut; that toggles the
            // hub on the focused monitor via the hubsByMonitor registry this
            // populates. A stale entry (monitor unplugged) becomes a null ref and
            // is skipped by focusedHub().
            Hub.HubWindow {
                id: hub
                screen: v.modelData
                theme: screenTheme
                stats: sysStats
                weatherState: weatherState
                notif: notifSvc
                Component.onCompleted: shellRoot.hubsByMonitor[v.modelData.name] = hub
            }

            // Toast popups (top-right, below the bar).
            Desktop.ToastOverlay {
                screen: v.modelData
                theme: screenTheme
                notif: notifSvc
            }
        }
    }
}
