import QtQuick
import QtQuick.Controls

// Past conversations shown in place of the message list. Newest first.
Item {
    id: root

    property var theme
    property var conversations: []
    property bool busy: false

    signal open(string id)
    signal remove(string id)

    readonly property string fontFamily: theme ? theme.fontFamily : "sans-serif"
    readonly property color fg: theme ? theme.text : "#e6e0e9"
    readonly property color fgDim: theme ? theme.textDim : "#cac4cf"
    readonly property color accent: theme ? theme.accent : "#d0bcff"
    readonly property color surfaceHigh: theme ? theme.surfaceHigh : "#2b292f"
    readonly property color line: theme ? theme.outline : "#49454e"
    readonly property color danger: theme ? theme.danger : "#f2b8b5"

    readonly property var entries: root.sorted()

    function sorted() {
        const list = (root.conversations || []).slice();
        list.sort((a, b) => (b.updated || 0) - (a.updated || 0));
        return list;
    }

    function relativeTime(ts) {
        const value = Number(ts) || 0;
        if (value <= 0) return "";
        const seconds = Math.max(0, (Date.now() - value) / 1000);
        if (seconds < 60) return "just now";
        if (seconds < 3600) return Math.floor(seconds / 60) + "m ago";
        if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago";
        if (seconds < 604800) return Math.floor(seconds / 86400) + "d ago";
        return new Date(value).toLocaleDateString();
    }

    function summary(conv) {
        let count = Number(conv.questions);
        if (!isFinite(count)) {
            const messages = conv.messages || [];
            count = 0;
            for (let i = 0; i < messages.length; i += 1) {
                if (messages[i].role === "user") count += 1;
            }
        }
        const label = count === 1 ? "1 question" : count + " questions";
        return label + " · " + root.relativeTime(conv.updated);
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 40
        visible: root.entries.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "No history yet.\nAsk something and it will show up here."
        color: root.fgDim
        opacity: 0.65
        font.family: root.fontFamily
        font.pixelSize: 11
        lineHeight: 1.25
    }

    ListView {
        anchors.fill: parent
        visible: root.entries.length > 0
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: root.entries
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
            id: row

            readonly property var conv: modelData

            width: ListView.view ? ListView.view.width : 320
            height: 52
            radius: 10
            color: rowHover.hovered ? root.surfaceHigh : "transparent"

            HoverHandler {
                id: rowHover
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.busy) return;
                    root.open(row.conv.id);
                }
            }

            Column {
                x: 10
                width: parent.width - 44
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    width: parent.width
                    text: row.conv.title && row.conv.title.length > 0 ? row.conv.title : "Untitled conversation"
                    color: root.fg
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    text: root.summary(row.conv)
                    color: root.fgDim
                    opacity: 0.8
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: 10
                }
            }

            Item {
                id: removeBtn
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                visible: rowHover.hovered

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: removeHover.containsMouse ? root.danger : root.fgDim
                    font.family: root.fontFamily
                    font.pixelSize: 11
                }

                MouseArea {
                    id: removeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.busy) return;
                        root.remove(row.conv.id);
                    }
                }
            }
        }
    }

    // A short hint above the list keeps the panel's purpose obvious.
    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: -2
        visible: root.entries.length > 0
        text: root.busy ? "busy…" : ""
        color: root.line
        font.family: root.fontFamily
        font.pixelSize: 9
    }
}
