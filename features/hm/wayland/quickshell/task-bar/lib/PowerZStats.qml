import QtQuick
import Quickshell
import "powerz.js" as PowerZ

// Shared ChargerLab POWER-Z KM003C reader. Polls lib/powerz.sh (2 s) while a
// consumer surface is open -- popupOpen from BatteryPopup, hubOpen from
// HubWindow -- and exposes the parsed reading. Instantiated ONCE at ShellRoot
// and threaded to both the bar battery popup and the hub battery card. The read
// is pure sysfs (via powerz.sh), so it never claims the USB interface and cannot
// lock the meter against another app.
QtObject {
    id: root

    // Consumer visibility inputs; OR'd into the poll gate. Named `polling` (not
    // `active`) so it never collides with the device `state` value "active".
    property bool popupOpen: false
    property bool hubOpen: false
    readonly property bool polling: root.popupOpen || root.hubOpen

    // Device state: "active" | "busy" | "absent" (see powerz.sh).
    property string state: "absent"
    readonly property bool available: root.state === "active"
    property real vbus: 0   // V
    property real ibus: 0   // A
    property real cc1: 0    // V (VCC1)
    property real cc2: 0    // V (VCC2)
    property real power: 0  // W (vbus * ibus)

    property CommandPoll poll: CommandPoll {
        interval: 2000
        running: root.polling
        command: [Quickshell.env("HOME") + "/.config/quickshell/task-bar/lib/powerz.sh"]
        parse: function (o) {
            return PowerZ.parsePowerz(o);
        }
        onUpdated: {
            var v = value || {};
            root.state = v.state || "absent";
            root.vbus = v.vbus || 0;
            root.ibus = v.ibus || 0;
            root.cc1 = v.cc1 || 0;
            root.cc2 = v.cc2 || 0;
            root.power = v.power || 0;
        }
    }
}
