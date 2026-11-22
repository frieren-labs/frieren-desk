import QtQuick
import QtQuick.Controls
import Quickshell

Item {
    id: panel

    property var theme
    property alias model: list.model

    function appendInput(text) {
        text = String(text || "");
        if (text.length === 0) return;
        const sep = input.text.length > 0 && !/\s$/.test(input.text) ? " " : "";
        input.text += sep + text;
        input.cursorPosition = input.text.length;
        input.forceActiveFocus();
    }

    // Slash/@ completion: matches while typing the first word.
    function slashMatches() {
        const t = input.text;
        if (t.length === 0 || (t[0] !== "/" && t[0] !== "@")) return [];
        if (/\s/.test(t)) return [];
        const pool = t[0] === "/" ? panel.slashCommands : panel.atCommands;
        const needle = t.toLowerCase();
        return pool.filter(c => c.cmd.toLowerCase().indexOf(needle) === 0);
    }

    function slashVisible() {
        return !panel.slashDismissed && !panel.busy && panel.slashMatches().length > 0;
    }

    function completeSlash(cmd) {
        input.text = cmd + " ";
        input.cursorPosition = input.text.length;
        input.forceActiveFocus();
    }

    // Drop files or screenshots: inserts @paths for opencode to read.
    function dropPaths(urls) {
        const parts = [];
        for (let i = 0; i < urls.length; i += 1) {
            let p = decodeURIComponent(String(urls[i] || ""));
            if (p.indexOf("file://") === 0) p = p.slice(7);
            if (p.length === 0) continue;
            parts.push(p.indexOf(" ") >= 0 ? '@"' + p + '"' : "@" + p);
        }
        if (parts.length > 0) panel.appendInput(parts.join(" ") + " ");
    }

    DropArea {
        anchors.fill: parent
        onDropped: drop => {
            if (drop.hasUrls) {
                panel.dropPaths(drop.urls);
                drop.accept();
            }
        }
        onEntered: drop => {
            if (drop.hasUrls) inputBox.border.color = panel.accent;
        }
        onExited: inputBox.border.color = input.activeFocus ? panel.accent : panel.line
    }
    property bool busy: false
    property bool hasSession: false
    property bool authMissing: false
    property var conversations: []
    property var searchResults: []
    property bool searching: false
    property var statsRows: []
    property bool statsLoading: false

    property bool historyOpen: false
    property bool historyFirst: false
    property bool statsOpen: false
    property bool dictating: false
    property bool slashDismissed: false
    property int slashIndex: 0

    readonly property var slashCommands: [
        { cmd: "/new", desc: "fresh conversation" },
        { cmd: "/retry", desc: "resend last prompt" },
        { cmd: "/export", desc: "copy conversation as Markdown" },
        { cmd: "/stats", desc: "open activity panel" },
        { cmd: "/model", desc: "switch model: /model provider/name" },
        { cmd: "/agent", desc: "switch agent: /agent name" },
        { cmd: "/sound", desc: "UI sounds: /sound on|off" },
        { cmd: "/voice", desc: "spoken replies: /voice on|off|id" },
        { cmd: "/volume", desc: "voice volume: /volume 10-150" },
        { cmd: "/help", desc: "list commands" }
    ]
    readonly property var atCommands: [
        { cmd: "@window", desc: "include focused Hyprland window" }
    ]

    signal submit(string text)
    signal stop()
    signal fresh()
    signal dismiss()
    signal dictate()
    signal configureAuth()
    signal openConversation(string id)
    signal deleteConversation(string id)
    signal exportRequested()
    signal statsRequested()
    signal searchHistory(string q)

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
                            text: panel.busy
                                ? "thinking…"
                                : panel.statsOpen
                                    ? "activity"
                                    : panel.historyOpen
                                        ? "history"
                                        : (panel.hasSession ? "active conversation" : "new conversation")
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
                        glyph: panel.historyOpen ? "‹" : "≡"
                        tooltip: panel.historyOpen ? "Back to chat" : "History"
                        onActivated: {
                            panel.historyOpen = !panel.historyOpen;
                            if (panel.historyOpen) panel.statsOpen = false;
                        }
                    }

                    IconButton {
                        theme: panel.theme
                        glyph: "⛁"
                        tooltip: "Copy conversation as Markdown"
                        onActivated: panel.exportRequested()
                    }

                    IconButton {
                        theme: panel.theme
                        glyph: "%"
                        tooltip: panel.statsOpen ? "Back to chat" : "Activity stats"
                        onActivated: {
                            panel.statsOpen = !panel.statsOpen;
                            if (panel.statsOpen) {
                                panel.historyOpen = false;
                                if (panel.statsRows.length === 0 && !panel.statsLoading)
                                    panel.statsRequested();
                            }
                        }
                    }

                    IconButton {
                        theme: panel.theme
                        glyph: "+"
                        tooltip: "New conversation"
                        onActivated: {
                            panel.historyOpen = false;
                            panel.statsOpen = false;
                            panel.fresh();
                        }
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

            // ---------- messages / history ----------
            Item {
                id: body
                width: parent.width
                height: parent.height - 34 - 10 - inputBox.height - 10
                    - (authBanner.visible ? authBanner.height + 10 : 0)

                ListView {
                    id: list
                    anchors.fill: parent
                    visible: !panel.historyOpen && !panel.statsOpen
                    clip: true
                    spacing: 12
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    // Follow the end only while the user is already there. Any
                    // upward scroll releases the lock so streaming text cannot
                    // drag the view back down.
                    property bool follow: true
                    property real lastY: 0
                    property real lastHeight: 0

                    delegate: MessageBubble {
                        theme: panel.theme
                        role: model.role
                        text: model.text
                        command: model.command
                        output: model.output
                        status: model.status
                        timestamp: model.ts
                    }

                    onCountChanged: {
                        if (list.count === 0
                                || (panel.model && panel.model.get(list.count - 1).role === "user"))
                            list.follow = true;
                        list.lastY = list.contentY;
                        if (list.follow) Qt.callLater(list.positionViewAtEnd);
                    }

                    onContentHeightChanged: if (list.follow) Qt.callLater(list.positionViewAtEnd)

                    onContentYChanged: {
                        // A height change (first layout, window resize) clamps
                        // contentY; that is not the user scrolling up.
                        const heightChanged = Math.abs(list.height - list.lastHeight) > 0.5;
                        if (!heightChanged && list.contentY < list.lastY - 0.5)
                            list.follow = false;
                        list.lastY = list.contentY;
                        list.lastHeight = list.height;
                    }

                    onAtYEndChanged: if (list.atYEnd) list.follow = true
                }

                HistoryPanel {
                    anchors.fill: parent
                    visible: panel.historyOpen && !panel.statsOpen
                    theme: panel.theme
                    conversations: panel.conversations
                    searchResults: panel.searchResults
                    searching: panel.searching
                    busy: panel.busy

                    onOpen: id => {
                        panel.historyOpen = false;
                        panel.openConversation(id);
                    }
                    onRemove: id => panel.deleteConversation(id)
                    onSearch: q => panel.searchHistory(q)
                }

                StatsPanel {
                    anchors.fill: parent
                    visible: panel.statsOpen
                    theme: panel.theme
                    rows: panel.statsRows
                    loading: panel.statsLoading

                    onRefresh: panel.statsRequested()
                }

                // Shown only when the view is released from the end.
                Rectangle {
                    visible: !list.follow && !panel.historyOpen && !panel.statsOpen && list.count > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    width: 84
                    height: 26
                    radius: 13
                    color: surfaceHigh
                    border.color: line
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "↓ Latest"
                        color: accent
                        font.family: fontFamily
                        font.pixelSize: 10
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            list.follow = true;
                            list.positionViewAtEnd();
                        }
                    }
                }
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
                    anchors.right: micBtn.left
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

                    function commit() {
                        if (text.trim().length === 0) return;
                        if (panel.slashVisible()) {
                            const m = panel.slashMatches();
                            panel.completeSlash(m[Math.min(panel.slashIndex, m.length - 1)].cmd);
                            return;
                        }
                        panel.historyOpen = false;
                        panel.historyFirst = false;
                        panel.statsOpen = false;
                        list.follow = true;
                        panel.submit(text.trim());
                        text = "";
                    }

                    onAccepted: commit()

                    onTextChanged: {
                        panel.slashIndex = 0;
                        if (text.length === 0 || (text[0] !== "/" && text[0] !== "@"))
                            panel.slashDismissed = false;
                    }

                    Keys.onUpPressed: event => {
                        const m = panel.slashMatches();
                        if (panel.slashVisible() && m.length > 0) {
                            panel.slashIndex = (panel.slashIndex - 1 + m.length) % m.length;
                            event.accepted = true;
                        }
                    }

                    Keys.onDownPressed: event => {
                        const m = panel.slashMatches();
                        if (panel.slashVisible() && m.length > 0) {
                            panel.slashIndex = (panel.slashIndex + 1) % m.length;
                            event.accepted = true;
                        }
                    }

                    Keys.onEscapePressed: {
                        if (panel.slashVisible()) panel.slashDismissed = true;
                        else panel.dismiss();
                    }
                }

                Rectangle {
                    id: micBtn
                    anchors.right: sendBtn.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    radius: 16
                    color: panel.dictating ? (theme ? theme.danger : "#f2b8b5") : "transparent"
                    border.color: panel.dictating ? "transparent" : (theme ? theme.outline : "#49454e")
                    border.width: 1
                    opacity: 0.95

                    Text {
                        anchors.centerIn: parent
                        text: panel.dictating ? "■" : "◉"
                        color: panel.dictating
                            ? (theme ? theme.accentText : "#381e72")
                            : (theme ? theme.textDim : "#cac4cf")
                        font.pixelSize: panel.dictating ? 12 : 16
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.dictate()
                    }
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
                            if (panel.busy) panel.stop();
                            else input.commit();
                        }
                    }
                }
            }

            // ---------- slash completion popup (overlay, drop-up) ----------
            Rectangle {
                id: slashPopup
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: inputBox.top
                anchors.bottomMargin: 6
                height: Math.min(12 + panel.slashMatches().length * 30, 192)
                visible: panel.slashVisible()
                radius: 12
                color: surfaceHigh
                border.color: line
                border.width: 1
                z: 10

                ListView {
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 0
                    boundsBehavior: Flickable.StopAtBounds
                    model: panel.slashMatches()

                    delegate: Rectangle {
                        width: ListView.view ? ListView.view.width - 12 : 360
                        height: 30
                        radius: 8
                        color: index === panel.slashIndex ? surface : "transparent"

                        Row {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                text: modelData.cmd
                                color: accent
                                font.family: fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: modelData.desc
                                color: fgDim
                                opacity: 0.85
                                elide: Text.ElideRight
                                width: parent.parent.width - 8 - parent.children[0].implicitWidth - 8 - 8
                                font.family: fontFamily
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        HoverHandler {
                            onHoveredChanged: if (hovered) panel.slashIndex = index
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.completeSlash(modelData.cmd)
                        }
                    }
                }
            }
        }
    }

    onVisibleChanged: if (visible) {
        historyOpen = historyFirst;
        historyFirst = false;
        statsOpen = false;
        list.follow = true;
        Qt.callLater(() => {
            list.positionViewAtEnd();
            input.forceActiveFocus();
        });
    }
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
