// features/hm/wayland/quickshell/task-bar/lock/lockbat-test.qml
// Unit test for LockBattery's pure formatting and state-line rules. Run:
//   quickshell -p features/hm/wayland/quickshell/task-bar/lock/lockbat-test.qml
// Expect a single "BAT-TEST PASS n/n" line.
//
// Sibling of the component on purpose: qs -p sandboxes imports to the
// entrypoint's parent directory, so a bare type name is the only way to
// resolve LockBattery (same as locksec-test.qml).
import QtQuick
import Quickshell
import Quickshell.Services.UPower

ShellRoot {
    LockBattery {
        id: bat
        theme: null
    }

    Component.onCompleted: {
        var pass = 0, total = 0;
        function check(name, got, want) {
            total++;
            if (got === want) pass++;
            else console.log("BAT-TEST CASE FAIL: " + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want));
        }

        // ---- duration formatting -----------------------------------------
        // 0 and negative mean "no estimate", NOT "zero minutes". UPower reports
        // 0 for several minutes after every plug/unplug while the kernel
        // re-estimates, and "0m left" on a healthy battery reads as an imminent
        // shutdown.
        check("dur/zero", bat._fmtDuration(0), "");
        check("dur/negative", bat._fmtDuration(-120), "");
        check("dur/59s", bat._fmtDuration(59), "1m");
        check("dur/60s", bat._fmtDuration(60), "1m");
        check("dur/59m", bat._fmtDuration(59 * 60), "59m");
        check("dur/1h", bat._fmtDuration(3600), "1h 00m");
        check("dur/90m", bat._fmtDuration(90 * 60), "1h 30m");
        check("dur/2h15", bat._fmtDuration(2 * 3600 + 15 * 60), "2h 15m");
        check("dur/25h", bat._fmtDuration(25 * 3600), "25h 00m");

        // ---- rate formatting ----------------------------------------------
        // At the charge cap the rate is genuinely 0 W; printing "0.0W" reads as
        // a measurement fault rather than as a resting battery.
        check("rate/zero", bat._fmtRate(0), "");
        check("rate/negative", bat._fmtRate(-5), "");
        check("rate/one", bat._fmtRate(12.14), "12.1W");
        check("rate/rounds", bat._fmtRate(44.96), "45.0W");

        // ---- join ---------------------------------------------------------
        check("join/both", bat._join("a", "b"), "a - b");
        check("join/firstOnly", bat._join("a", ""), "a");
        check("join/secondOnly", bat._join("", "b"), "b");
        check("join/neither", bat._join("", ""), "");

        // ---- state lines ---------------------------------------------------
        check("state/discharging",
              bat._stateLine(UPowerDeviceState.Discharging, 2 * 3600 + 15 * 60, 0, 12.1),
              "2h 15m left - 12.1W");
        check("state/charging",
              bat._stateLine(UPowerDeviceState.Charging, 0, 3600 + 5 * 60, 45.0),
              "1h 05m until full - 45.0W");

        // The common case on this machine: an 80% charge cap holds the battery
        // at pending-charge with a zero rate and NO time estimate at all.
        check("state/pendingCharge",
              bat._stateLine(UPowerDeviceState.PendingCharge, 0, 0, 0),
              "On AC - charge limited");
        check("state/pendingDischarge",
              bat._stateLine(UPowerDeviceState.PendingDischarge, 0, 0, 0),
              "On AC");
        check("state/full", bat._stateLine(UPowerDeviceState.FullyCharged, 0, 0, 0), "Fully charged");
        check("state/empty", bat._stateLine(UPowerDeviceState.Empty, 0, 0, 0), "Empty");
        check("state/unknown", bat._stateLine(UPowerDeviceState.Unknown, 0, 0, 0), "");

        // A missing estimate drops ONLY its own clause, never the whole line.
        check("state/dischargingNoTime",
              bat._stateLine(UPowerDeviceState.Discharging, 0, 0, 12.1), "12.1W");
        check("state/dischargingNoRate",
              bat._stateLine(UPowerDeviceState.Discharging, 3600, 0, 0), "1h 00m left");
        check("state/dischargingNeither",
              bat._stateLine(UPowerDeviceState.Discharging, 0, 0, 0), "");
        check("state/chargingNoTime",
              bat._stateLine(UPowerDeviceState.Charging, 0, 0, 45.0), "45.0W");

        // Discharging must read timeToEmpty and charging must read timeToFull.
        // Swapping them still produces a plausible-looking line, so assert the
        // wrong field is ignored.
        check("state/dischargingIgnoresToFull",
              bat._stateLine(UPowerDeviceState.Discharging, 0, 9999, 0), "");
        check("state/chargingIgnoresToEmpty",
              bat._stateLine(UPowerDeviceState.Charging, 9999, 0, 0), "");

        // ---- low tint ------------------------------------------------------
        // Only while DISCHARGING. On AC at 15% is not an alarm -- it is a
        // machine that was just plugged in, and tinting it red teaches the user
        // to ignore the colour.
        check("low/discharging", bat._isLow(UPowerDeviceState.Discharging, 15, 20), true);
        check("low/atThreshold", bat._isLow(UPowerDeviceState.Discharging, 20, 20), true);
        check("low/aboveThreshold", bat._isLow(UPowerDeviceState.Discharging, 21, 20), false);
        check("low/chargingSamePct", bat._isLow(UPowerDeviceState.Charging, 15, 20), false);
        check("low/pendingSamePct", bat._isLow(UPowerDeviceState.PendingCharge, 15, 20), false);
        check("low/fullSamePct", bat._isLow(UPowerDeviceState.FullyCharged, 15, 20), false);

        // ---- percent -------------------------------------------------------
        check("pct/rounds-down", bat._fmtPct(79.4), 79);
        check("pct/rounds-up", bat._fmtPct(79.5), 80);
        check("pct/clampsHigh", bat._fmtPct(103), 100);
        check("pct/clampsLow", bat._fmtPct(-2), 0);

        console.log(pass === total ? ("BAT-TEST PASS " + pass + "/" + total)
                                   : ("BAT-TEST FAIL " + pass + "/" + total));
        Qt.quit();
    }
}
