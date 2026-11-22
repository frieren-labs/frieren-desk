import QtQuick
import Quickshell

// Copies `text` to the Wayland clipboard and shows a check mark for a moment.
// The icon is drawn with rectangles so it does not depend on a glyph being
// present in the theme font.
Item {
    id: btn

    property var theme
    property string text: ""
    property string tooltip: "Copy"
    property bool copied: false

    signal activated()

    readonly property color line: theme ? theme.outline : "#49454e"
    readonly property color ok: theme ? theme.ok : "#7fff9a"

    width: 22
    height: 22

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: hover.containsMouse ? (theme ? theme.surfaceHigh : "#2b292f") : "transparent"
    }

    // two offset rounded rectangles: the usual copy icon
    Rectangle {
        visible: !btn.copied && btn.text.length > 0
        x: 6
        y: 8
        width: 9
        height: 10
        radius: 2
        color: "transparent"
        border.color: hover.containsMouse ? (theme ? theme.text : "#e6e0e9") : btn.line
        border.width: 1
    }

    Rectangle {
        visible: !btn.copied && btn.text.length > 0
        x: 8
        y: 5
        width: 9
        height: 10
        radius: 2
        color: theme ? theme.surfaceHigh : "#2b292f"
        border.color: hover.containsMouse ? (theme ? theme.text : "#e6e0e9") : btn.line
        border.width: 1
    }

    Text {
        anchors.centerIn: parent
        visible: btn.copied
        text: "✓"
        color: btn.ok
        font.family: theme ? theme.fontFamily : "sans-serif"
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Timer {
        id: reset
        interval: 1200
        onTriggered: btn.copied = false
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (btn.text.length === 0) return;
            Quickshell.clipboardText = btn.text;
            btn.copied = true;
            reset.restart();
            btn.activated();
        }
    }
}
