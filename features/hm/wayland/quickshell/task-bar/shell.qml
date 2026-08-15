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
import "lock" as Lock

ShellRoot {
    id: shellRoot

    // Global notification service (one server for all screens).
    Lib.NotifService {
        id: notifSvc
    }

    // Who is capturing right now (mic / camera / screencast), read by the bar's
    // media pill. Id `captureSvc` MUST differ from the `capture` property it
    // feeds on Taskbar: an own-property shadows the outer-component id across
    // the Variants delegate, so a same-name binding resolves to the widget's
    // own null property (see submapSvc / netSvc / powerzStats above).
    Lib.CaptureService {
        id: captureSvc
        // captureArmed as well as locked: Lock.qml starts its backdrop
        // ScreencopyView (which Hyprland counts as a screencast) 25-250ms
        // BEFORE it sets locked, and the desktop is still composited in that
        // window -- so the pill flashed a red recording glyph caused by the
        // lock's own backdrop on every single lock. captureArmed is cleared
        // again in Lock.qml's unlock branch, so this adds no lasting state.
        locked: lockScreen.locked || lockScreen.captureArmed
        castCount: shellRoot.screencastCount
        castOwner: shellRoot.castOwner
        castTarget: shellRoot.castTarget
    }

    // Global lock: one WlSessionLock manages every output. Instantiated once
    // (not per-screen) -- the surface Component is created per output internally.
    Lock.Lock {
        id: lockScreen
        audio: audioSvc
        notifications: notifSvc
        // Ids differ from the property names they feed (netSvc->net,
        // e5800Svc->router, btSvc->bt): an own-property shadows an enclosing
        // component's id in QML scope resolution, so a same-name binding
        // silently resolves to the component's own null property.
        net: netSvc
        router: e5800Svc
        bt: btSvc
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

    // Last-resume publisher. One reader for all screens. The id differs from
    // the Taskbar `wakeSvc` property it feeds, for the same shadowing reason as
    // e5800Svc->routerSvc directly above.
    Lib.WakeService {
        id: resumeMonitor
    }

    // Shared CPU/RAM poller, read by every bar + hub header. One /proc reader for
    // all screens (was one per monitor).
    Lib.SysStats {
        id: sysStats
    }

    // Background multi-city weather watcher: tier-polls every city (geo fast, the
    // rest slow), diffs conditions, and notify-sends start/clear transitions. One
    // instance for all screens; no per-monitor state needed.
    Lib.WeatherWatch {
    }

    // Shared POWER-Z KM003C reader (bar battery popup + hub battery card). One
    // gated sysfs poll for all screens. Id `powerzStats` MUST differ from the
    // `powerz` property it feeds on Taskbar/HubWindow -- an own-property shadows
    // the outer id across the Variants delegate (see netSvc/routerSvc/submapSvc).
    Lib.PowerZStats {
        id: powerzStats
    }

    // Host-side USB-C charger/PD state (EC RAM via the ec-pd-poll service). Read
    // by the battery popup. Id `ecPdSvc` differs from the `ecPd` property it feeds
    // (Variants delegate shadowing), matching powerzStats/netSvc/e5800Svc.
    Lib.EcPdService {
        id: ecPdSvc
    }

    // Mirror Hyprland's screencast state into the notification service so toasts
    // are suppressed while screen sharing -- the QS-native replacement for the
    // swaync screencast inhibitor (see quickshell-notifications-cutover). The
    // `screencast` IPC event carries `state,owner`; state 1 = sharing, 0 = off.
    //
    // This MUST be a refcount, not a last-write-wins flag: the event is PER
    // SESSION, not a global refcount, and the lock's own workspace backdrop
    // (ScreencopyView) opens a screencast session every lock and closes it at
    // unlock. A last-write-wins flag latches false the moment our backdrop's
    // session closes, even while a real capture (wf-recorder, a portal share)
    // is still running and will never re-announce -- a false all-clear on the
    // feature's flagship signal. Counting sessions instead means our own
    // open/close pair nets to zero without touching a concurrent real one.
    //
    // Clamped at 0 with Math.max: if qs restarts mid-cast it misses that
    // session's opening `1` and under-counts by one until the next state
    // change re-syncs it (rare, and only costs a few un-suppressed toasts).
    // Without the clamp, that missed-opening under-count could go negative on
    // the matching `0` and latch `screencasting` false, reintroducing the
    // exact false-all-clear this refcount exists to prevent.
    //
    // Qualified `shellRoot.` deliberately: an unqualified assignment to a
    // property that no longer resolves fails SOFT in QML JS -- the read yields
    // undefined, Math.max(0, NaN) is NaN, `NaN > 0` is false, and screencasting
    // latches permanently false. That is silently the same false all-clear this
    // refcount exists to prevent, so the reference must fail loudly instead.
    property int screencastCount: 0
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "screencast") {
                var sharing = event.parse(2)[0] === "1";
                shellRoot.screencastCount = Math.max(0, shellRoot.screencastCount + (sharing ? 1 : -1));
                notifSvc.screencasting = shellRoot.screencastCount > 0;
            }
        }
    }

    // Active casts, newest last. A STACK rather than a single owner/target
    // pair, because Hyprland's events carry no session identity: the lock's
    // own workspace backdrop opens a screencast session on every lock, and a
    // single pair would let that session's irrelevant values overwrite a real
    // share's attribution with nothing to restore it afterwards.
    //
    // Stops are matched LIFO. That is an approximation -- the wire format
    // gives nothing to correlate a stop with its start -- but it is exact for
    // the case that actually occurs here: the backdrop's session opens after,
    // and closes before, any share it overlaps.
    //
    // Deliberately does NOT consult screencastCount. That counter is
    // maintained by a different handler on a different event, and gating the
    // clear on it leaves a stale title behind whenever the two events arrive
    // in the unexpected order.
    property var castStack: []
    readonly property string castOwner: shellRoot.castStack.length > 0 ? shellRoot.castStack[shellRoot.castStack.length - 1].owner : ""
    readonly property string castTarget: shellRoot.castStack.length > 0 ? shellRoot.castStack[shellRoot.castStack.length - 1].target : ""
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "screencastv2")
                return;
            var f = event.parse(3);
            // Copy-then-reassign: mutating the array in place does not fire a
            // change notification, so bindings would silently never update.
            var next = shellRoot.castStack.slice();
            if (f[0] === "1")
                next.push({
                    owner: f[1] || "",
                    target: f[2] || ""
                });
            else
                next.pop();
            shellRoot.castStack = next;
        }
    }

    // hy3 group/tab transitions leave Quickshell's *incremental* toplevel model
    // stale for now-hidden windows (their lastIpcObject loses `class`/`workspace`),
    // so iconFor() gets "" and a tab group of N renders as one invisible slot. A
    // full refreshToplevels() re-syncs every field. Driven ONCE here at ShellRoot
    // -- refreshToplevels() updates the shared Hyprland.toplevels that every bar
    // reads, so a per-monitor copy (the old Taskbar location) only multiplied the
    // `hyprctl clients` spawns by the monitor count. Debounced so an event burst
    // collapses into one refresh; windowtitle* is excluded (terminals spam it).
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "openwindow":
            case "closewindow":
            case "movewindowv2":
            case "activewindowv2":
            // Taskbar.surfaceVisible reads each toplevel's fullscreen flag to
            // decide whether this bar is covered, so it needs the same refresh.
            // `fullscreen` is its own event, but it is NOT emitted when a
            // fullscreen window simply closes -- that is closewindow, already
            // above. Both paths must land here or the bar stays gated off.
            case "fullscreen":
                toplevelRefresh.restart();
                break;
            }
        }
    }
    Timer {
        id: toplevelRefresh
        interval: 150
        repeat: false
        onTriggered: Hyprland.refreshToplevels()
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
                capture: captureSvc
                submap: submapSvc
                calState: calState
                routerSvc: e5800Svc
                net: netSvc
                inhibit: inhibitSvc
                powerz: powerzStats
                ecPd: ecPdSvc
                wakeSvc: resumeMonitor
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
                powerz: powerzStats
                net: netSvc
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
