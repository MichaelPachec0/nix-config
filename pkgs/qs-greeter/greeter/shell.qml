import Quickshell
import Quickshell.Wayland
import QtQuick
import "screens" as Screens

ShellRoot {
    id: shellRoot

    Component.onCompleted: {
        Session.backend = greetdBackend;
        if (!greetdBackend.available)
            Log.error("greetd is not available (GREETD_SOCK unset)");
    }

    GreetdBackend { id: greetdBackend }

    // Backdrop.qml declares its own `required property var modelData`; Variants
    // sets that property directly from each model item, so the delegate here
    // must NOT redeclare or bind it itself. `Screens.Backdrop { modelData:
    // modelData }` would be a self-referential binding (the property reading
    // itself) and never receive the actual screen.
    Variants {
        model: Quickshell.screens
        Screens.Backdrop {}
    }

    // Latches true the first time the walking-skeleton auto-launch actually
    // fires, so launch() is called at most once per shell lifetime no matter
    // how many times _maybeLaunch() is re-entered (Session state settling,
    // Sessions finishing its load, or both in either order). Without this,
    // a stray re-entry (e.g. Session cycling back through "ready") would call
    // backend.launch() a second time on top of an already-launching session.
    property bool _autoLaunched: false

    // Ready to launch requires BOTH Session having reached "ready" (greetd's
    // side is done) AND Sessions having settled (the wrapper's sessions.json
    // FileView has loaded or failed -- see Sessions.qml). Gating on Session
    // state alone races: if greetd reaches "ready" before the session list
    // has loaded, Sessions.list is still its initial empty array and this
    // would silently no-op forever, since onStateChanged only re-fires on
    // Session's own state changes, never on Sessions arriving later.
    function _maybeLaunch() {
        if (shellRoot._autoLaunched) return;
        if (Session.state !== "ready") return;
        if (!Sessions.ready) return;
        if (Sessions.list.length === 0) return;
        shellRoot._autoLaunched = true;
        Session.launch(Sessions.list[0]);
    }

    PanelWindow {
        id: login
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: greetdBackend.available
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "qs-greeter:login"
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        Rectangle {
            anchors.centerIn: parent
            width: 420
            height: 220
            color: "#ECE9D8"
            border { width: 1; color: "#716F64" }

            Column {
                anchors.centerIn: parent
                spacing: 10

                TextField_ {
                    id: userField
                    label: "User name:"
                    echoMode: TextInput.Normal
                    text: "michael"
                }
                TextField_ {
                    id: secretField
                    label: Session.promptLabel || "Password:"
                    echoMode: Session.promptSecret ? TextInput.Password : TextInput.Normal
                    enabled: Session.promptLabel !== ""
                    onAccepted: Session.submit(text)
                }
                Text {
                    text: Session.waitingForDevice
                        ? "Waiting for your security key..."
                        : Session.statusText
                    color: Session.statusIsError ? "#a00000" : "#303030"
                }
                Row {
                    spacing: 8
                    Button_ {
                        text: "OK"
                        onClicked: {
                            if (Session.state === "idle" || Session.state === "failed")
                                Session.begin(userField.text);
                            else
                                Session.submit(secretField.text);
                        }
                    }
                    Button_ { text: "Cancel"; onClicked: Session.cancel() }
                }
            }
        }

        // Ready -> launch the first session. Task 10 adds the picker.
        Connections {
            target: Session
            function onStateChanged() { shellRoot._maybeLaunch(); }
        }

        Connections {
            target: Sessions
            function onReadyChanged() { shellRoot._maybeLaunch(); }
        }
    }

    // Minimal inline controls; replaced by the skin's widget kit in Task 9.
    component TextField_: Row {
        property alias text: input.text
        property alias echoMode: input.echoMode
        property alias enabled: input.enabled
        property string label: ""
        signal accepted()
        spacing: 8
        Text { text: parent.label; width: 90 }
        Rectangle {
            width: 220; height: 22; color: "white"
            border { width: 1; color: "#716F64" }
            TextInput {
                id: input
                anchors.fill: parent
                anchors.margins: 3
                onAccepted: parent.parent.accepted()
            }
        }
    }

    component Button_: Rectangle {
        property alias text: label.text
        signal clicked()
        width: 80; height: 24
        color: ma.pressed ? "#D6D2C2" : "#ECE9D8"
        border { width: 1; color: "#716F64" }
        Text { id: label; anchors.centerIn: parent }
        MouseArea { id: ma; anchors.fill: parent; onClicked: parent.clicked() }
    }
}
