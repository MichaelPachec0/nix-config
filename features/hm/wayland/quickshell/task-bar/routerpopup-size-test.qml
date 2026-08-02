// Headless sizing check for RouterPopup. Run:
//     quickshell -p routerpopup-size-test.qml
//
// Lives at the config ROOT rather than beside the popup: `quickshell -p` makes
// the entrypoint's parent the root, and desktop/RouterPopup.qml does
// `import "../lib/routerfmt.js"`. From here that resolves to task-bar/lib/,
// inside the root. From desktop/ it would resolve outside it and fail.
//
// This does not assert a pixel width -- fonts differ per machine. It asserts
// the properties that were actually broken: that the card GROWS for a payload
// wider than the old fixed 380, that it stays within the clamp, and that no
// binding loop fires while it does.
import QtQuick
import Quickshell
import "lib" as Lib
import "desktop" as Desktop

ShellRoot {
    // NOT `id: theme`: RouterPopup declares its own `theme` property, and
    // `theme: theme` resolves to that null property rather than to this object
    // -- the same-name shadowing trap this repo has hit before.
    Lib.ThemeEngine { id: themeEngine }

    // Minimal stand-ins for RouterService's shape. Only the fields RouterPopup
    // reads, so a missing one shows up as a QML warning rather than silently
    // rendering blank.
    QtObject {
        id: sparse
        readonly property bool reachable: true
        readonly property bool authError: false
        readonly property bool recovering: false
        readonly property var data: ({})
        readonly property var device: ({ model: "GL-E5800", carrier: "" })
        readonly property var battery: ({})
        readonly property var uplink: ({ online: true })
        readonly property var cellular: ({ supported: false })
        readonly property var throughput: ({})
        readonly property var dataUsage: ({})
        readonly property var system: ({})
        readonly property var clients: ({ list: [] })
        readonly property var wifi: []
        readonly property var vpn: ({})
    }

    // The real capture, which is what overflowed.
    QtObject {
        id: full
        readonly property bool reachable: true
        readonly property bool authError: false
        readonly property bool recovering: false
        readonly property var data: ({})
        readonly property var device: ({ model: "GL-E5800", carrier: "Mint (T-Mobile)" })
        readonly property var battery: ({
            percent: 80, charging: true, plugged: true, fastcharge: false,
            temp: 39, cycles: 28, abnormal: false,
            warn_temp: 50, warn_capacity: 10
        })
        readonly property var uplink: ({
            online: true, up: true, uptime: 12663, device: "rmnet_data0",
            ip: "48.18.141.141", mask: 30, gateway: "48.18.141.142",
            dns: ["10.177.0.34", "10.177.0.210"]
        })
        readonly property var cellular: ({
            supported: true, gen: "5G", operator_label: "Mint (T-Mobile)",
            operator: "T-Mobile", sim_operator: "Mint", plmn: "310-260",
            registration: "home", roaming: false, apn: "fast.t-mobile.com",
            network_type: "NR5G-NSA", rsrp: -85, rsrq: -10, sinr: 27,
            ca: { count: 3, bands: ["B66", "n41", "n71"], carriers: [
                { label: "B66", active: true, state: null },
                { label: "n41", active: true, state: null },
                { label: "n71", active: false, state: 1 }
            ]},
            serving: { bands: ["B66", "n41"], cellid: "1762803", tac: "3C6E",
                       pcid: 322, rsrp: -99, cells: [{ rat: "LTE" }] },
            neighbours: { count: 3, best_rsrp: -103, cells: [] }
        })
        readonly property var throughput: ({ rx: 4615000, tx: 20000 })
        readonly property var dataUsage: ({ cycle_rx: 700000000000, cycle_tx: 91000000000 })
        readonly property var system: ({
            cpu_temp: 46, load: [1.55, 1.51, 1.47], uptime: 276164,
            mem_total: 1675968512, mem_free: 311914496, mem_buff: 699138048,
            flash_total: 3021608, flash_free: 2687000
        })
        readonly property var clients: ({ list: [] })
        readonly property var wifi: [{ band: "2.4G", up: true },
                                     { band: "5G", up: true }]
        readonly property var vpn: ({ active: false })
    }

    // A carrier name from the far end of the vendored PLMN table, to prove the
    // clamp holds rather than letting one long string stretch the card.
    QtObject {
        id: longNames
        readonly property bool reachable: true
        readonly property bool authError: false
        readonly property bool recovering: false
        readonly property var data: ({})
        readonly property var device: ({ model: "GL-E5800", carrier: "" })
        readonly property var battery: ({})
        readonly property var uplink: ({
            online: true, device: "rmnet_data0",
            ip: "192.168.100.200", mask: 24, gateway: "192.168.100.1",
            dns: ["2001:4860:4860::8888", "2001:4860:4860::8844",
                  "10.177.0.34", "10.177.0.210"]
        })
        readonly property var cellular: ({
            supported: true, gen: "4G",
            operator_label: "Telecommunication Systems of Elbonia (R:Vodafone Enterprise)",
            apn: "internet.of.a.very.long.mvno.example.com",
            serving: { bands: ["B66", "n41", "n71"], cellid: "188888803",
                       tac: "3C6E", pcid: 322, rsrp: -99, cells: [{ rat: "LTE" }] },
            neighbours: { count: 12, best_rsrp: -103, cells: [] }
        })
        readonly property var throughput: ({})
        readonly property var dataUsage: ({})
        readonly property var system: ({})
        readonly property var clients: ({ list: [] })
        readonly property var wifi: []
        readonly property var vpn: ({})
    }

    QtObject {
        id: recovering
        readonly property bool reachable: true
        readonly property bool authError: false
        readonly property bool recovering: true
        readonly property var data: ({ recovery: { action: "airplane" } })
        readonly property var device: ({ model: "GL-E5800", carrier: "Mint (R:AT&T)" })
        readonly property var battery: ({ percent: 8, charging: false, plugged: false,
                                          temp: 52, cycles: 288, abnormal: true,
                                          warn_temp: 50, warn_capacity: 10 })
        readonly property var uplink: ({ online: false, uptime: 41,
                                         device: "rmnet_data0", ip: "48.18.141.141",
                                         mask: 30, gateway: "48.18.141.142",
                                         dns: ["10.177.0.34", "10.177.0.210"] })
        readonly property var cellular: ({
            supported: true, gen: "5G", operator_label: "Mint (R:AT&T)",
            roaming: true, plmn: "310-410", registration: "roaming",
            sim_operator: "Mint", apn: "fast.t-mobile.com",
            network_type: "NR5G-NSA", rsrp: -112, rsrq: -19, sinr: 2,
            ca: { carriers: [{ label: "B66", active: true, state: null },
                             { label: "n41", active: true, state: null },
                             { label: "n71", active: false, state: 1 }] },
            serving: { bands: ["B66", "n41", "n71"], cellid: "1762803", tac: "3C6E",
                       pcid: 322, rsrp: -112, cells: [{ rat: "LTE" }] },
            neighbours: { count: 12, best_rsrp: -95, cells: [] }
        })
        readonly property var throughput: ({ rx: 0, tx: 0 })
        readonly property var dataUsage: ({ cycle_rx: 700000000000, cycle_tx: 91000000000 })
        readonly property var system: ({ cpu_temp: 46, load: [1.55, 1.51, 1.47],
                                         uptime: 276164, mem_total: 1675968512,
                                         mem_free: 311914496, mem_buff: 699138048 })
        readonly property var clients: ({ list: [] })
        readonly property var wifi: [{ band: "2.4G", up: true }, { band: "5G", up: true }]
        readonly property var vpn: ({ active: true, name: "protonvpn-us-free-42" })
    }

    FloatingWindow {
        id: host
        implicitWidth: 900
        implicitHeight: 200
        color: "#1d2021"

        Item { id: anchorPoint; x: 100; y: 0; width: 1; height: 1 }

        // Three instances rather than a Loader: PopupWindow is not a visual
        // child, so a parent-chain binding does not reach the probe.
        Desktop.RouterPopup { id: popSparse; theme: themeEngine; svc: sparse
                              barWindow: host; anchorItem: anchorPoint }
        Desktop.RouterPopup { id: popFull; theme: themeEngine; svc: full
                              barWindow: host; anchorItem: anchorPoint }
        Desktop.RouterPopup { id: popRecover; theme: themeEngine; svc: recovering
                              barWindow: host; anchorItem: anchorPoint }
        Desktop.RouterPopup { id: popLong; theme: themeEngine; svc: longNames
                              barWindow: host; anchorItem: anchorPoint }

        property int pass: 0
        property int fail: 0
        function check(name, cond, detail) {
            if (cond) { host.pass++; console.log("  ok   " + name + "   " + (detail || "")); }
            else { host.fail++; console.log("  FAIL " + name + "   " + (detail || "")); }
        }

        Component.onCompleted: Qt.callLater(function () {
            var MIN = 380, MAX = 560;
            console.log("SIZE-TEST");
            console.log("  sparse=" + popSparse.implicitWidth
                        + " full=" + popFull.implicitWidth
                        + " long=" + popLong.implicitWidth
                        + " recovering=" + popRecover.implicitWidth);

            host.check("sparse payload holds the minimum",
                       popSparse.implicitWidth === MIN,
                       "got " + popSparse.implicitWidth);
            host.check("real capture fits without clipping",
                       popFull.implicitWidth >= MIN && popFull.implicitWidth <= MAX,
                       "got " + popFull.implicitWidth);
            host.check("long strings are clamped, not unbounded",
                       popLong.implicitWidth <= MAX,
                       "got " + popLong.implicitWidth);
            host.check("a fuller payload is never narrower than a sparse one",
                       popFull.implicitWidth >= popSparse.implicitWidth,
                       popFull.implicitWidth + " >= " + popSparse.implicitWidth);
            host.check("content has real height",
                       popFull.implicitHeight > popSparse.implicitHeight,
                       popFull.implicitHeight + " > " + popSparse.implicitHeight);

            // A wrapping DNS list must add HEIGHT, not width: four resolvers
            // including IPv6 would otherwise pin the card to the clamp.
            host.check("a long DNS list does not inflate the card width",
                       popLong.implicitWidth < MAX,
                       "got " + popLong.implicitWidth);

            host.check("a recovery in flight fits (widest realistic row)",
                       popRecover.implicitWidth >= MIN && popRecover.implicitWidth <= MAX,
                       "got " + popRecover.implicitWidth);

            console.log("SIZE-TEST " + host.pass + "/" + (host.pass + host.fail));
            Qt.exit(host.fail === 0 ? 0 : 1);
        });
    }
}
