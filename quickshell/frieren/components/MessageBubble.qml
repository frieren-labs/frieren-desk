import QtQuick

Item {
    id: root

    width: ListView.view ? ListView.view.width - 28 : 380
    implicitHeight: col.height

    property var theme
    property string role: "assistant"
    property string text: ""
    property string command: ""
    property string output: ""
    property string status: ""
    property var timestamp: 0

    readonly property string fontFamily: theme ? theme.fontFamily : "sans-serif"
    readonly property string monoFamily: theme ? theme.monoFamily : "monospace"
    readonly property color fg: theme ? theme.text : "#e6e0e9"
    readonly property color fgDim: theme ? theme.textDim : "#cac4cf"
    readonly property color accent: theme ? theme.accent : "#d0bcff"
    readonly property color panel: theme ? theme.background : "#141218"
    readonly property color line: theme ? theme.outline : "#49454e"
    readonly property color danger: theme ? theme.danger : "#f2b8b5"
    readonly property color ok: theme ? theme.ok : "#7fff9a"
    readonly property color selectionColor: theme ? theme.primaryContainer : "#4f378b"
    readonly property color selectionText: theme ? theme.primaryContainerText : "#e6e0e9"

    readonly property string outputPreview: {
        const value = String(root.output || "");
        const lines = value.split("\n");
        if (lines.length <= 10) return value;
        return lines.slice(0, 10).join("\n") + "\n…";
    }

    HoverHandler {
        id: hover
    }

    Column {
        id: col
        width: parent.width
        spacing: 8

        // ---- user message ----
        Rectangle {
            visible: root.role === "user"
            x: col.width - width
            width: col.width * 0.88
            height: userText.contentHeight + 20
            radius: 14
            color: root.theme ? root.theme.primaryContainer : "#4f378b"

            TextEdit {
                id: userText
                x: 12
                y: 10
                width: parent.width - 24
                height: contentHeight
                text: root.text
                color: root.theme ? root.theme.primaryContainerText : "#e6e0e9"
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                cursorVisible: false
                selectionColor: root.selectionColor
                selectedTextColor: root.selectionText
                font.family: root.fontFamily
                font.pixelSize: 13
            }
        }

        // ---- Frieren's reply (Markdown) ----
        Item {
            visible: root.role === "assistant" && root.text.length > 0
            width: col.width
            height: reply.height

            MarkdownText {
                id: reply
                width: parent.width
                theme: root.theme
                text: root.text
            }

            // Lives in the right margin of the delegate, so it never covers
            // the text and does not reserve extra height.
            CopyButton {
                x: parent.width + 4
                y: 0
                theme: root.theme
                text: root.text
                tooltip: "Copy reply"
                opacity: hover.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }

        // ---- executed action (log) ----
        Rectangle {
            visible: root.role === "tool"
            width: col.width
            height: toolCol.height + 20
            radius: 10
            color: root.panel
            border.color: root.status === "error" ? root.danger : root.line
            border.width: 1

            Column {
                id: toolCol
                x: 10
                y: 10
                width: parent.width - 20
                spacing: 6

                Item {
                    width: parent.width
                    height: Math.max(commandText.implicitHeight, 20)

                    Rectangle {
                        id: statusDot
                        width: 7
                        height: 7
                        radius: 4
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.topMargin: 6
                        color: root.status === "error" ? root.danger
                            : root.status === "running" ? root.accent
                            : root.ok
                    }

                    Text {
                        id: commandText
                        anchors.left: statusDot.right
                        anchors.leftMargin: 6
                        anchors.right: toolCopy.left
                        anchors.rightMargin: 6
                        text: root.command.length > 0 ? root.command : (root.text.length > 0 ? root.text : "action")
                        color: root.fgDim
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        font.family: root.monoFamily
                        font.pixelSize: 11
                        lineHeight: 1.2
                    }

                    CopyButton {
                        id: toolCopy
                        anchors.right: parent.right
                        anchors.top: parent.top
                        theme: root.theme
                        text: root.command.length > 0 ? root.command : root.text
                        tooltip: "Copy command"
                    }
                }

                TextEdit {
                    visible: root.output.length > 0
                    width: toolCol.width
                    height: contentHeight
                    text: root.outputPreview
                    color: root.status === "error" ? root.danger : root.fgDim
                    opacity: 0.75
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    readOnly: true
                    selectByMouse: true
                    persistentSelection: true
                    cursorVisible: false
                    selectionColor: root.selectionColor
                    selectedTextColor: root.selectionText
                    font.family: root.monoFamily
                    font.pixelSize: 10
                }
            }
        }

        // ---- system notices ----
        TextEdit {
            visible: root.role === "system"
            width: col.width
            height: contentHeight
            text: root.text
            color: root.fgDim
            opacity: 0.8
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            readOnly: true
            selectByMouse: true
            persistentSelection: true
            cursorVisible: false
            selectionColor: root.selectionColor
            selectedTextColor: root.selectionText
            font.family: root.fontFamily
            font.pixelSize: 11
            font.italic: true
        }
    }
}
