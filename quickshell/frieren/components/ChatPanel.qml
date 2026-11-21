import QtQuick
import QtQuick.Controls
import Quickshell

Item {
    id: panel

    property var theme
    property alias model: list.model
    property bool busy: false
    property bool hasSession: false
    property bool authMissing: false

    signal submit(string text)
    signal stop()
    signal fresh()
    signal dismiss()
    signal configureAuth()

    readonly property string fontFamily: theme ? theme.fontFamily : "sans-serif"
    readonly property color fg: theme ? theme.text : "#e6e0e9"
    readonly property color fgDim: theme ? theme.textDim : "#cac4cf"
    readonly property color accent: theme ? theme.accent : "#d0bcff"
    readonly property color surface: theme ? theme.surface : "#211f24"
    readonly property color surfaceHigh: theme ? theme.surfaceHigh : "#2b292f"
    readonly property color line: theme ? theme.outline : "#49454e"
    readonly property color danger: theme ? theme.danger : "#f2b8b5"

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: surface
        border.color: line
        border.width: 1

        MouseArea {
            anchors.fill: parent
            onClicked: input.forceActiveFocus()
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ---------- header ----------
            Item {
                width: parent.width
                height: 34

                Row {
                    spacing: 9
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        width: 30
                        height: 30
                        source: "file://" + (Quickshell.env("HOME") || "") + "/.config/quickshell/frieren/assets/frieren-icon.png"
                        fillMode: Image.PreserveAspectFit
                        smooth: false
                        sourceSize: Qt.size(60, 60)
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            text: "Frieren"
                            color: fg
                            font.family: fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: panel.busy ? "thinking…" : (panel.hasSession ? "active conversation" : "new conversation")
                            color: panel.busy ? accent : fgDim
                            opacity: 0.85
                            font.family: fontFamily
                            font.pixelSize: 10
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    IconButton {
                        theme: panel.theme
                        glyph: "+"
                        tooltip: "New conversation"
                        onActivated: panel.fresh()
                    }

                    IconButton {
                        theme: panel.theme
                        glyph: "✕"
                        tooltip: "Close"
                        onActivated: panel.dismiss()
                    }
                }
            }

            // ---------- opencode account banner ----------
            Rectangle {
                id: authBanner
                visible: panel.authMissing
                width: parent.width
                height: 38
                radius: 10
                color: surfaceHigh
                border.color: danger
                border.width: 1

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: connectLabel.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "OpenCode is not connected."
                    color: fg
                    font.family: fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                Text {
                    id: connectLabel
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Connect"
                    color: accent
                    font.family: fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.configureAuth()
                }
            }

            // ---------- messages ----------
            ListView {
                id: list
                width: parent.width
                height: parent.height - 34 - 10 - inputBox.height - 10
                    - (authBanner.visible ? authBanner.height + 10 : 0)
                clip: true
                spacing: 12
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: MessageBubble {
                    theme: panel.theme
                    role: model.role
                    text: model.text
                    command: model.command
                    output: model.output
                    status: model.status
                }

                onCountChanged: Qt.callLater(positionViewAtEnd)
                onContentHeightChanged: if (!moving) Qt.callLater(positionViewAtEnd)
            }

            // ---------- input ----------
            Rectangle {
                id: inputBox
                width: parent.width
                height: 44
                radius: 12
                color: surfaceHigh
                border.color: input.activeFocus ? accent : line
                border.width: 1

                TextInput {
                    id: input
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: sendBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: fg
                    font.family: fontFamily
                    font.pixelSize: 13
                    selectByMouse: true
                    clip: true
                    enabled: !panel.busy

                    Text {
                        anchors.fill: parent
                        visible: input.text.length === 0
                        text: panel.busy ? "wait for it to finish or stop it…" : "ask me something about the system…"
                        color: fgDim
                        opacity: 0.6
                        font: input.font
                        verticalAlignment: Text.AlignVCenter
                    }

                    onAccepted: {
                        if (text.trim().length > 0) {
                            panel.submit(text.trim());
                            text = "";
                        }
                    }

                    Keys.onEscapePressed: panel.dismiss()
                }

                Rectangle {
                    id: sendBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    radius: 16
                    color: panel.busy ? (theme ? theme.danger : "#f2b8b5") : accent
                    opacity: 0.95

                    Text {
                        anchors.centerIn: parent
                        text: panel.busy ? "■" : "→"
                        color: theme ? theme.accentText : "#381e72"
                        font.pixelSize: panel.busy ? 12 : 16
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (panel.busy) {
                                panel.stop();
                            } else if (input.text.trim().length > 0) {
                                panel.submit(input.text.trim());
                                input.text = "";
                            }
                        }
                    }
                }
            }
        }
    }

    onVisibleChanged: if (visible) Qt.callLater(input.forceActiveFocus)
    Component.onCompleted: Qt.callLater(input.forceActiveFocus)

    // ---------- reusable small button ----------
    component IconButton: Rectangle {
        id: btn

        property var theme
        property string glyph: ""
        property string tooltip: ""
        signal activated()

        width: 26
        height: 26
        radius: 13
        color: hover.containsMouse ? (theme ? theme.surfaceHigh : "#2b292f") : "transparent"

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: theme ? theme.textDim : "#cac4cf"
            font.family: theme ? theme.fontFamily : "sans-serif"
            font.pixelSize: 14
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }
}
