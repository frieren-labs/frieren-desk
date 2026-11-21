import QtQuick

Item {
    id: dialog

    property var theme
    property string provider: ""
    property string model: ""
    // unknown | checking | connected | missing | error
    property string status: "unknown"
    property string detail: ""
    property string message: ""
    property bool messageOk: false
    property bool messageError: false
    property bool checking: false
    property bool busy: false

    signal saveKey(string key)
    signal terminalLogin()
    signal check()
    signal close()

    readonly property bool connected: status === "connected"
    readonly property string fontFamily: theme ? theme.fontFamily : "sans-serif"
    readonly property color fg: theme ? theme.text : "#e6e0e9"
    readonly property color fgDim: theme ? theme.textDim : "#cac4cf"
    readonly property color accent: theme ? theme.accent : "#d0bcff"
    readonly property color accentText: theme ? theme.accentText : "#381e72"
    readonly property color surface: theme ? theme.surface : "#211f24"
    readonly property color surfaceHigh: theme ? theme.surfaceHigh : "#2b292f"
    readonly property color line: theme ? theme.outline : "#49454e"
    readonly property color danger: theme ? theme.danger : "#f2b8b5"
    readonly property color ok: theme ? theme.ok : "#7fff9a"

    readonly property color statusColor: {
        if (dialog.status === "connected") return dialog.ok;
        if (dialog.status === "missing" || dialog.status === "error") return dialog.danger;
        return dialog.accent;
    }

    readonly property string statusLabel: {
        if (dialog.checking && !dialog.connected) return "Checking...";
        if (dialog.connected) return "Connected";
        if (dialog.status === "missing") return "Not connected";
        if (dialog.status === "error") return "Check failed";
        return "Checking...";
    }

    readonly property string statusText: {
        if (dialog.connected)
            return dialog.detail.length > 0
                ? "Signed in with: " + dialog.detail
                : "opencode has a credential for this provider.";
        if (dialog.status === "missing")
            return "No credentials for " + dialog.provider + " yet.";
        if (dialog.status === "error")
            return dialog.detail;
        return "Reading the opencode credentials...";
    }

    implicitWidth: 430
    implicitHeight: card.height

    function focusKey() {
        keyInput.forceActiveFocus();
    }

    function clearKey() {
        keyInput.text = "";
    }

    Shortcut {
        sequence: "Escape"
        enabled: dialog.visible
        onActivated: dialog.close()
    }

    Rectangle {
        id: card
        width: parent.width
        height: column.implicitHeight + 32
        radius: 18
        color: dialog.surface
        border.color: dialog.line
        border.width: 1

        Column {
            id: column
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 12

            // ---------- header ----------
            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "OpenCode account"
                    color: dialog.fg
                    font.family: dialog.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                IconButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    theme: dialog.theme
                    glyph: "✕"
                    tooltip: "Close"
                    onActivated: dialog.close()
                }
            }

            // ---------- status ----------
            Item {
                width: parent.width
                height: statusColumn.height

                Rectangle {
                    id: statusDot
                    width: 8
                    height: 8
                    radius: 4
                    color: dialog.statusColor
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.topMargin: 5
                }

                Column {
                    id: statusColumn
                    anchors.left: statusDot.right
                    anchors.leftMargin: 8
                    anchors.right: checkLink.left
                    anchors.rightMargin: 8
                    spacing: 2

                    Text {
                        width: parent.width
                        text: dialog.statusLabel
                        color: dialog.statusColor
                        font.family: dialog.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Text {
                        width: parent.width
                        text: dialog.statusText
                        color: dialog.fgDim
                        font.family: dialog.fontFamily
                        font.pixelSize: 10
                        wrapMode: Text.Wrap
                        visible: text.length > 0
                    }
                }

                Text {
                    id: checkLink
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: "Check"
                    color: dialog.accent
                    opacity: dialog.checking || dialog.busy ? 0.4 : 1
                    font.family: dialog.fontFamily
                    font.pixelSize: 10

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: !dialog.checking && !dialog.busy
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dialog.check()
                    }
                }
            }

            // ---------- account info ----------
            Text {
                width: parent.width
                text: "Provider: " + dialog.provider + "   Model: " + dialog.model
                color: dialog.fgDim
                opacity: 0.85
                font.family: dialog.fontFamily
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            // ---------- API key ----------
            Rectangle {
                width: parent.width
                height: 42
                radius: 10
                color: dialog.surfaceHigh
                border.color: keyInput.activeFocus ? dialog.accent : dialog.line
                border.width: 1

                TextInput {
                    id: keyInput
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    color: dialog.fg
                    font.family: dialog.fontFamily
                    font.pixelSize: 13
                    selectByMouse: true
                    clip: true
                    enabled: !dialog.busy
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                    passwordMaskDelay: 0

                    onAccepted: {
                        if (text.trim().length > 0) {
                            dialog.saveKey(text.trim());
                        }
                    }

                    Keys.onEscapePressed: dialog.close()

                    Text {
                        anchors.fill: parent
                        visible: keyInput.text.length === 0
                        text: "Paste your API key"
                        color: dialog.fgDim
                        opacity: 0.6
                        font: keyInput.font
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // ---------- actions ----------
            Row {
                width: parent.width
                spacing: 8

                ActionButton {
                    theme: dialog.theme
                    label: dialog.busy ? "Saving..." : "Save key"
                    primary: true
                    enabled: !dialog.busy && keyInput.text.trim().length > 0
                    onActivated: dialog.saveKey(keyInput.text.trim())
                }

                ActionButton {
                    theme: dialog.theme
                    label: "Terminal login"
                    enabled: !dialog.busy
                    onActivated: dialog.terminalLogin()
                }
            }

            Text {
                width: parent.width
                visible: dialog.message.length > 0
                text: dialog.message
                color: dialog.messageError
                    ? dialog.danger
                    : (dialog.messageOk ? dialog.ok : dialog.fgDim)
                font.family: dialog.fontFamily
                font.pixelSize: 10
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                text: "The key is stored by opencode, not by Frieren. Use terminal login for providers that need a browser, like GitHub Copilot."
                color: dialog.fgDim
                opacity: 0.65
                font.family: dialog.fontFamily
                font.pixelSize: 9
                wrapMode: Text.Wrap
            }
        }
    }

    // ---------- reusable buttons ----------
    component IconButton: Rectangle {
        id: iconBtn

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
            text: iconBtn.glyph
            color: theme ? theme.textDim : "#cac4cf"
            font.family: theme ? theme.fontFamily : "sans-serif"
            font.pixelSize: 14
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: iconBtn.activated()
        }
    }

    component ActionButton: Rectangle {
        id: actionBtn

        property var theme
        property string label: ""
        property bool primary: false
        signal activated()

        width: actionText.implicitWidth + 26
        height: 34
        radius: 10
        color: !actionBtn.enabled
            ? (theme ? theme.surfaceHigh : "#2b292f")
            : (actionBtn.primary ? (theme ? theme.accent : "#d0bcff") : "transparent")
        border.color: actionBtn.primary && actionBtn.enabled
            ? "transparent"
            : (theme ? theme.outline : "#49454e")
        border.width: actionBtn.primary && actionBtn.enabled ? 0 : 1
        opacity: actionBtn.enabled ? 1 : 0.85

        Text {
            id: actionText
            anchors.centerIn: parent
            text: actionBtn.label
            color: !actionBtn.enabled
                ? (theme ? theme.textDim : "#cac4cf")
                : (actionBtn.primary
                    ? (theme ? theme.accentText : "#381e72")
                    : (theme ? theme.text : "#e6e0e9"))
            font.family: theme ? theme.fontFamily : "sans-serif"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: actionBtn.activated()
        }
    }
}
