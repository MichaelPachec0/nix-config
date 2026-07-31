// features/hm/wayland/quickshell/task-bar/lock/LockBattery.qml
// Battery block, top-left on the lock, above the security column. Percent plus
// a state line carrying time remaining and charge rate.
//
// Reads Quickshell.Services.UPower directly -- no probe script and no poll.
// Every other signal on this lock needs a probe because nothing native reports
// it; battery is the one that answers completely over D-Bus, and should stay
// that way.
//
// All text-producing logic lives in the pure functions below, taking explicit
// arguments rather than reading UPower, because a headless fixture cannot
// inject a D-Bus service. Logic that reads UPower directly is untestable, and
// this repo has already shipped two tests that passed against the unfixed code
// for exactly that reason.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

ColumnLayout {
    id: root

    property var theme: null
    property real contentOpacity: 1.0
    property int lowPercent: 20

    spacing: 2
    opacity: root.contentOpacity

    // --- pure core (covered by lockbat-test.qml) --------------------------

    // "" means NO ESTIMATE, which is different from zero minutes. UPower
    // reports 0 for several minutes after every plug and unplug while the
    // kernel re-estimates; rendering "0m left" on a healthy battery reads as an
    // imminent shutdown, so the caller drops the clause entirely instead.
    function _fmtDuration(sec) {
        if (!(sec > 0))
            return "";
        var m = Math.round(sec / 60);
        if (m < 1)
            return "";
        if (m < 60)
            return m + "m";
        var h = Math.floor(m / 60);
        var rem = m % 60;
        return h + "h " + (rem < 10 ? "0" : "") + rem + "m";
    }

    // Same contract: "" means no reading. At the charge cap the rate is
    // genuinely 0 W, and "0.0W" reads as a broken sensor rather than a resting
    // battery.
    function _fmtRate(w) {
        if (!(w > 0))
            return "";
        return w.toFixed(1) + "W";
    }

    function _join(a, b) {
        if (a && b)
            return a + " - " + b;
        return a || b || "";
    }

    // Selected by state, because that is what actually differs between cases.
    // PendingCharge is the COMMON case on a machine with a charge cap, not an
    // edge case: it holds there for most of its plugged-in life.
    function _stateLine(state, toEmptySec, toFullSec, rateW) {
        var rate = root._fmtRate(rateW);
        switch (state) {
        case UPowerDeviceState.Discharging:
            var left = root._fmtDuration(toEmptySec);
            return root._join(left ? (left + " left") : "", rate);
        case UPowerDeviceState.Charging:
            var full = root._fmtDuration(toFullSec);
            return root._join(full ? (full + " until full") : "", rate);
        case UPowerDeviceState.PendingCharge:
            return "On AC - charge limited";
        case UPowerDeviceState.PendingDischarge:
            return "On AC";
        case UPowerDeviceState.FullyCharged:
            return "Fully charged";
        case UPowerDeviceState.Empty:
            return "Empty";
        default:
            return "";
        }
    }

    // Discharging only. On AC at 15% is not an alarm -- it is a machine that
    // was just plugged in, and tinting that red teaches the user to ignore the
    // colour everywhere else.
    function _isLow(state, pct, threshold) {
        return state === UPowerDeviceState.Discharging && pct <= threshold;
    }

    function _fmtPct(pct) {
        return Math.round(Math.min(100, Math.max(0, pct)));
    }
}
