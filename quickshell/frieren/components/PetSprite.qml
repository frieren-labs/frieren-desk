import QtQuick
import Quickshell

Item {
    id: root

    width: 168
    height: 188

    property bool busy: false
    property bool hovered: mouse.containsMouse || mouse.drag.active

    signal activate()
    signal moved(real x, real y)

    readonly property string home: Quickshell.env("HOME") || ""

    // Cuerpo animado. root.x / root.y son la posicion real (drag), por eso
    // el bob se aplica al item interno y no al root.
    Item {
        id: body
        anchors.fill: parent
        scale: root.hovered ? 1.04 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Item {
            id: bobbing
            anchors.fill: parent
            y: 0

            SequentialAnimation on y {
                running: true
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: -5; duration: root.busy ? 900 : 2200; easing.type: Easing.InOutSine }
                NumberAnimation { from: -5; to: 0; duration: root.busy ? 900 : 2200; easing.type: Easing.InOutSine }
            }

            SequentialAnimation on rotation {
                running: true
                loops: Animation.Infinite
                NumberAnimation { from: -1.2; to: 1.2; duration: 3400; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.2; to: -1.2; duration: 3400; easing.type: Easing.InOutSine }
            }

            Image {
                id: sprite
                anchors.fill: parent
                source: "file://" + root.home + "/.config/quickshell/frieren/assets/frieren-chibi.png"
                fillMode: Image.PreserveAspectFit
                smooth: false
                asynchronous: true
            }
        }

        // Halo suave cuando esta trabajando
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.92
            height: width
            radius: width / 2
            color: "#d0bcff"
            opacity: root.busy ? 0.10 : 0.0
            z: -1
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
    }

    // Etiqueta de estado / ayuda
    Rectangle {
        id: hint
        visible: root.busy || root.hovered
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: -6
        width: label.implicitWidth + 18
        height: 24
        radius: 12
        color: "#211f24"
        border.color: "#49454e"
        border.width: 1
        opacity: 0.96

        Text {
            id: label
            anchors.centerIn: parent
            text: root.busy ? "pensando…" : "preguntame algo"
            color: root.busy ? "#d0bcff" : "#cac4cf"
            font.family: "Google Sans Flex"
            font.pixelSize: 11
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: mouse.drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        drag.target: root
        drag.axis: Drag.XAndYAxis
        drag.minimumX: 0
        drag.maximumX: Math.max(0, root.parent ? root.parent.width - root.width : 0)
        drag.minimumY: 0
        drag.maximumY: Math.max(0, root.parent ? root.parent.height - root.height : 0)

        property bool moved: false

        onPressed: moved = false
        onPositionChanged: if (drag.active) moved = true
        onReleased: {
            root.moved(root.x, root.y);
            if (!moved) root.activate();
        }
    }
}
