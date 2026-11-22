import QtQuick
import QtQuick.Controls

// Activity dashboard: per-day turns from frieren.db (turns/tools/daily).
Item {
    id: root

    property var theme
    property var rows: []
    property bool loading: false

    signal refresh()

    readonly property string fontFamily: theme ? theme.fontFamily : "sans-serif"
    readonly property color fg: theme ? theme.text : "#e6e0e9"
    readonly property color fgDim: theme ? theme.textDim : "#cac4cf"
    readonly property color accent: theme ? theme.accent : "#d0bcff"
    readonly property color surfaceHigh: theme ? theme.surfaceHigh : "#2b292f"
    readonly property color line: theme ? theme.outline : "#49454e"

    function totals() {
        let turns = 0;
        let ok = 0;
        for (let i = 0; i < rows.length; i += 1) {
            turns += Number(rows[i].turns) || 0;
            ok += Number(rows[i].ok_turns) || 0;
        }
        return {
            turns: turns,
            pct: turns > 0 ? Math.round(1000 * ok / turns) / 10 : 0
        };
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 40
        visible: !root.loading && root.rows.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "No activity yet.\nTurns and tool calls will show up here."
        color: root.fgDim
        opacity: 0.65
        font.family: root.fontFamily
        font.pixelSize: 11
        lineHeight: 1.25
    }

    Text {
        anchors.centerIn: parent
        visible: root.loading && root.rows.length === 0
        text: "loading…"
        color: root.line
        font.family: root.fontFamily
        font.pixelSize: 11
    }

    Column {
        anchors.fill: parent
        spacing: 8
        visible: root.rows.length > 0 || root.loading

        Item {
            width: parent.width
            height: 30

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const t = root.totals();
                    return "Last " + root.rows.length + "d · " + t.turns + " turns · " + t.pct + "% ok";
                }
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.loading ? "loading…" : "Refresh"
                color: root.accent
                opacity: root.loading ? 0.5 : 1
                font.family: root.fontFamily
                font.pixelSize: 10

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    enabled: !root.loading
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refresh()
                }
            }
        }

        // header
        Item {
            width: parent.width
            height: 16

            Row {
                anchors.fill: parent
                spacing: 0

                Text { width: parent.width * 0.30; text: "day"; color: root.fgDim; opacity: 0.7; font.family: root.fontFamily; font.pixelSize: 9 }
                Text { width: parent.width * 0.22; text: "turns"; color: root.fgDim; opacity: 0.7; font.family: root.fontFamily; font.pixelSize: 9; horizontalAlignment: Text.AlignRight }
                Text { width: parent.width * 0.24; text: "ok %"; color: root.fgDim; opacity: 0.7; font.family: root.fontFamily; font.pixelSize: 9; horizontalAlignment: Text.AlignRight }
                Text { width: parent.width * 0.24; text: "avg ms"; color: root.fgDim; opacity: 0.7; font.family: root.fontFamily; font.pixelSize: 9; horizontalAlignment: Text.AlignRight }
            }
        }

        ListView {
            width: parent.width
            height: parent.height - 30 - 16 - 24 - 16
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.rows
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                width: ListView.view ? ListView.view.width : 380
                height: 24
                radius: 6
                color: "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 2
                    anchors.rightMargin: 2

                    Text { width: parent.width * 0.30; text: modelData.day || ""; color: root.fg; font.family: root.fontFamily; font.pixelSize: 11; elide: Text.ElideRight }
                    Text { width: parent.width * 0.22; text: String(modelData.turns || 0); color: root.fgDim; font.family: root.fontFamily; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
                    Text { width: parent.width * 0.24; text: String(modelData.ok_pct || 0) + "%"; color: root.fgDim; font.family: root.fontFamily; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
                    Text { width: parent.width * 0.24; text: String(modelData.avg_ms || 0); color: root.fgDim; font.family: root.fontFamily; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
                }
            }
        }

        Text {
            width: parent.width
            text: "Details: frieren-stats in a terminal."
            color: root.fgDim
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: 9
        }
    }
}
