import QtQuick

// The skin contract. A skin drives the core singletons through this surface;
// it never talks to greetd directly, and it never reaches past Session/
// Sessions into Settings for anything privileged. Stub for Task 8 -- the
// widgets and screens that make this an actual XP-styled logon are Task 10.
Item {
    id: root
    property var session: null
    property var sessions: null
    property var palette: null
    signal requestPower(string action)
}
