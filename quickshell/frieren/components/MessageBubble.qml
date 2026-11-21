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

    readonly property string fontFamily: theme ? theme.fontFamily : "sans-serif"
    readonly property string monoFamily: theme ? theme.monoFamily : "monospace"
    readonly property color fg: theme ? theme.text : "#e6e0e9"
    readonly property color fgDim: theme ? theme.textDim : "#cac4cf"
    readonly property color accent: theme ? theme.accent : "#d0bcff"
    readonly property color panel: theme ? theme.background : "#141218"
    readonly property color line: theme ? theme.outline : "#49454e"

    Column {
        id: col
        width: parent.width
        spacing: 8

        // ---- mensaje del usuario ----
        Rectangle {
            visible: root.role === "user"
            x: col.width - width
            width: col.width * 0.88
            height: userText.height + 20
            radius: 14
            color: root.theme ? root.theme.primaryContainer : "#4f378b"

            Text {
                id: userText
                x: 12
                y: 10
                width: parent.width - 24
                text: root.text
                color: root.theme ? root.theme.primaryContainerText : "#e6e0e9"
                wrapMode: Text.Wrap
                font.family: root.fontFamily
                font.pixelSize: 13
                lineHeight: 1.15
            }
        }

        // ---- respuesta de Frieren ----
        Text {
            visible: root.role === "assistant" && root.text.length > 0
            width: col.width
            text: root.text
            color: root.fg
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: 13
            lineHeight: 1.25
        }

        // ---- accion ejecutada (bitacora) ----
        Rectangle {
            visible: root.role === "tool"
            width: col.width
            height: toolCol.height + 20
            radius: 10
            color: root.panel
            border.color: root.status === "error" ? (root.theme ? root.theme.danger : "#f2b8b5") : root.line
            border.width: 1

            Column {
                id: toolCol
                x: 10
                y: 10
                width: parent.width - 20
                spacing: 6

                Row {
                    spacing: 6

                    Rectangle {
                        width: 7
                        height: 7
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.status === "error" ? (root.theme ? root.theme.danger : "#f2b8b5")
                             : root.status === "running" ? root.accent
                             : (root.theme ? root.theme.ok : "#7fff9a")
                    }

                    Text {
                        text: root.command.length > 0 ? root.command : (root.text.length > 0 ? root.text : "acción")
                        width: toolCol.width - 20
                        color: root.fgDim
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        font.family: root.monoFamily
                        font.pixelSize: 11
                        lineHeight: 1.2
                    }
                }

                Text {
                    visible: root.output.length > 0
                    width: toolCol.width
                    text: root.output
                    color: root.status === "error" ? (root.theme ? root.theme.danger : "#f2b8b5") : root.fgDim
                    opacity: 0.75
                    wrapMode: Text.Wrap
                    maximumLineCount: 10
                    elide: Text.ElideRight
                    font.family: root.monoFamily
                    font.pixelSize: 10
                    lineHeight: 1.2
                }
            }
        }

        // ---- avisos del sistema ----
        Text {
            visible: root.role === "system"
            width: col.width
            text: root.text
            color: root.fgDim
            opacity: 0.8
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: 11
            font.italic: true
        }
    }
}
