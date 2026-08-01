// features/hm/wayland/quickshell/task-bar/lock/locknet-test.qml
// Unit test for LockNetwork's pure row-composition rules. Run:
//   quickshell -p features/hm/wayland/quickshell/task-bar/lock/locknet-test.qml
// Expect a single "NET-TEST PASS n/n" line.
import QtQuick
import Quickshell

ShellRoot {
    // qualityFn is injected, not imported: `import "../lib/routerfmt.js"`
    // fails when this file is the quickshell -p entrypoint (lib/ falls outside
    // the config root). The stub RECORDS its arguments rather than replicating
    // routerfmt's bands -- asserting band values against a local reimplementation
    // would only be testing the stub. routerfmt.quality has its own Deno suite;
    // what belongs here is which metric LockNetwork feeds it.
    property string lastMetric: ""
    property var lastValue: null
    property int qualityCalls: 0

    LockNetwork {
        id: net
        theme: null
        qualityFn: function (metric, value) {
            lastMetric = metric;
            lastValue = value;
            qualityCalls++;
            return "STUB";
        }
    }

    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (got === want) pass++;
            else console.log("NET-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
        }

        // ---- link row ------------------------------------------------------
        // Wifi signal is a PERCENT from nmcli, never dBm.
        check("link/wifi", net._linkText("wifi", "activated", "MySSID", 75, true), "MySSID  75%");
        check("link/wifi-noSsidShown", net._linkText("wifi", "activated", "MySSID", 75, false), "Connected  75%");
        // Hiding the name must NOT also hide the signal -- the percentage is
        // not identifying and is half the value of the row.
        check("link/wifi-hidden-keepsSignal", net._linkText("wifi", "activated", "MySSID", 75, false).indexOf("75%") >= 0, true);
        // A wifi link with no SSID reported yet still reads as connected.
        check("link/wifi-noSsid", net._linkText("wifi", "activated", "", 60, true), "Connected  60%");
        // Zero signal is a real reading (nmcli reports 0), not "unknown".
        check("link/wifi-zeroSignal", net._linkText("wifi", "activated", "MySSID", 0, true), "MySSID  0%");
        check("link/ethernet", net._linkText("ethernet", "activated", "", 0, true), "Ethernet");
        check("link/none", net._linkText("none", "disconnected", "", 0, true), "Disconnected");
        // Associating but not yet up is not "connected".
        check("link/activating", net._linkText("wifi", "activating", "MySSID", 40, true), "Connecting");

        // ---- trouble row ---------------------------------------------------
        check("trouble/portal", net._troubleText("portal", true), "Captive portal");
        check("trouble/limited", net._troubleText("limited", true), "No internet");
        check("trouble/none", net._troubleText("none", true), "No internet");
        check("trouble/full", net._troubleText("full", true), "");
        // NetworkManager reports "unknown" before its first check and when the
        // check is disabled; treating it as an outage would fire every boot.
        check("trouble/unknown-silent", net._troubleText("unknown", true), "");
        // A disconnected machine has no internet by definition; saying so twice
        // helps nobody and makes the red row routine.
        check("trouble/linkDown-silent", net._troubleText("none", false), "");

        // ---- vpn row -------------------------------------------------------
        check("vpn/one", net._vpnText([{ name: "wg-home", active: true }]), "VPN: wg-home");
        check("vpn/two", net._vpnText([{ name: "wg-home", active: true }, { name: "corp", active: true }]), "VPN: wg-home, corp");
        // Inactive profiles exist in the list at all times; only active ones count.
        check("vpn/inactiveIgnored", net._vpnText([{ name: "wg-home", active: false }]), "");
        check("vpn/mixed", net._vpnText([{ name: "off", active: false }, { name: "on", active: true }]), "VPN: on");
        check("vpn/empty", net._vpnText([]), "");
        check("vpn/null", net._vpnText(null), "");

        // ---- cellular row --------------------------------------------------
        var cell = { supported: true, operator: "T-Mobile", gen: "5G", rsrp: -88, sinr: 20 };
        check("cell/full", net._cellText(cell), "T-Mobile 5G  -88 dBm");
        // rsrp is dBm; asserting the unit explicitly because swapping it with
        // the wifi percentage still looks plausible.
        check("cell/unitIsDbm", net._cellText(cell).indexOf("dBm") >= 0, true);
        // operator is null whenever no cell is camped. "Unknown 5G" reads as a
        // fault, so the name is simply dropped.
        check("cell/noOperator", net._cellText({ supported: true, operator: null, gen: "5G", rsrp: -88 }), "5G  -88 dBm");
        check("cell/noGen", net._cellText({ supported: true, operator: "T-Mobile", gen: null, rsrp: -88 }), "T-Mobile  -88 dBm");
        check("cell/noRsrp", net._cellText({ supported: true, operator: "T-Mobile", gen: "5G", rsrp: null }), "T-Mobile 5G");
        // Gated on `supported`, not on any single metric being present.
        check("cell/unsupported", net._cellText({ supported: false, operator: "T-Mobile", gen: "5G", rsrp: -88 }), "");
        check("cell/emptyObject", net._cellText({}), "");
        check("cell/null", net._cellText(null), "");

        // ---- operator label --------------------------------------------------
        // An MVNO's brand lives on the SIM and its network does not: a Mint SIM
        // rides T-Mobile, and both halves are worth showing. The collector
        // composes the string; the row must PREFER it over the bare network
        // name, or the MVNO name never reaches the screen.
        check("cell/label", net._cellText({ supported: true, operator_label: "Mint (T-Mobile)", operator: "T-Mobile", gen: "5G", rsrp: -88 }), "Mint (T-Mobile) 5G  -88 dBm");
        // A payload written before the poller carried the label (or a SIM with
        // no SPN record) still names the network.
        check("cell/labelFallback", net._cellText({ supported: true, operator: "T-Mobile", gen: "5G", rsrp: -88 }), "T-Mobile 5G  -88 dBm");
        check("cell/labelNullFallsBack", net._cellText({ supported: true, operator_label: null, operator: "T-Mobile", gen: "5G", rsrp: -88 }), "T-Mobile 5G  -88 dBm");

        // Roaming is marked on the network half by the collector, so the row
        // needs no rule of its own -- but assert it survives the row rather
        // than being reformatted away.
        check("cell/roamingLabel", net._cellText({ supported: true, operator_label: "Mint (R:AT&T)", operator: "AT&T", gen: "4G", rsrp: -95 }), "Mint (R:AT&T) 4G  -95 dBm");

        // ---- cellular tint: which metric feeds quality() ---------------------
        // The load-bearing choice. A congested cell reports strong rsrp and
        // poor sinr while throughput collapses, so feeding rsrp here would call
        // that healthy -- the everyday failure this row exists to expose.
        qualityCalls = 0; lastMetric = ""; lastValue = null;
        check("cellQ/passesThrough", net._cellQuality({ rsrp: -70, sinr: -3 }), "STUB");
        check("cellQ/metricIsSinr", lastMetric, "sinr");
        check("cellQ/valueIsSinrNotRsrp", lastValue, -3);

        // quality() answers "poor" for a null value, which would paint a warning
        // tint on a router that simply has no reading yet. _cellQuality must
        // guard BEFORE calling it: no reading, no verdict, and no call at all.
        qualityCalls = 0;
        check("cellQ/noSinr", net._cellQuality({ rsrp: -88, sinr: null }), "");
        check("cellQ/noSinr-doesNotCall", qualityCalls, 0);
        check("cellQ/null", net._cellQuality(null), "");
        check("cellQ/undefinedSinr", net._cellQuality({ rsrp: -88 }), "");
        check("cellQ/stillNoCalls", qualityCalls, 0);

        // ---- tint mapping ----------------------------------------------------
        check("tint/excellent", net._cellNeedsWarn("excellent"), false);
        check("tint/good", net._cellNeedsWarn("good"), false);
        check("tint/fair", net._cellNeedsWarn("fair"), true);
        check("tint/poor", net._cellNeedsWarn("poor"), true);
        check("tint/unknown", net._cellNeedsWarn(""), false);

        // ---- bluetooth row --------------------------------------------------
        check("bt/one", net._btText([{ deviceName: "Pixel Buds Pro" }]), "Pixel Buds Pro");
        check("bt/two", net._btText([{ deviceName: "Pixel Buds Pro" }, { deviceName: "Mouse" }]), "Pixel Buds Pro, Mouse");
        // BlueZ leaves Name empty for nameless devices; fall back to the
        // address rather than rendering an empty entry or a stray comma.
        check("bt/nameless", net._btText([{ deviceName: "", address: "AA:BB:CC:DD:EE:FF" }]), "AA:BB:CC:DD:EE:FF");
        check("bt/empty", net._btText([]), "");
        check("bt/null", net._btText(null), "");

        console.log(pass === total ? ("NET-TEST PASS " + pass + "/" + total)
                                   : ("NET-TEST FAIL " + pass + "/" + total));
        Qt.quit();
    }
}
