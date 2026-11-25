import QtQuick

Item {
    id: dialog

    property var theme
    property string tab: "pet"

    // Pet
    property bool wanderEnabled: true
    property bool sleepEnabled: true
    property bool blinkEnabled: true
    property real petScale: 1.0

    // Sound and voice
    property bool soundEnabled: true
    property bool voiceSpeak: false
    property string voiceId: ""
    property int voiceVolume: 100
    property var voices: []
    property bool voicesLoading: false

    // Data
    property bool logEnabled: true
    property bool discordEnabled: false

    // Model and account (passed through to the embedded AuthDialog)
    property string authProvider: ""
    property string modelName: ""
    property var models: []
    property bool modelsLoading: false
    property string authStatus: "unknown"
    property string authDetail: ""
    property string authMessage: ""
    property bool authMessageOk: false
    property bool authMessageError: false
    property bool authChecking: false
    property bool authBusy: false

    signal pickTab(string id)
    signal toggleSetting(string key)
    signal scaleSelected(real value)
    signal resetPosition()
    signal pickVoice(string id)
    signal volumeSelected(int value)
    signal testVoice()
    signal runBackup()
    signal testDiscord()
    signal saveModel(string id)
    signal saveKey(string key)
    signal terminalLogin()
    signal checkAuth()
    signal close()

    readonly property string fontFamily: theme ? theme.fontFamily : "sans-serif"
    readonly property color fg: theme ? theme.text : "#e6e0e9"
    readonly property color fgDim: theme ? theme.textDim : "#cac4cf"
    readonly property color accent: theme ? theme.accent : "#d0bcff"
    readonly property color accentText: theme ? theme.accentText : "#381e72"
    readonly property color surface: theme ? theme.surface : "#211f24"
    readonly property color surfaceHigh: theme ? theme.surfaceHigh : "#2b292f"
    readonly property color line: theme ? theme.outline : "#49454e"

    implicitWidth: 700
    implicitHeight: 580

    Shortcut {
        sequence: "Escape"
        enabled: dialog.visible
        onActivated: dialog.close()
    }

    Rectangle {
        id: card
        width: parent.width
        height: parent.height
        radius: 18
        color: dialog.surface
        border.color: dialog.line
        border.width: 1

        Column {
            id: column
            x: 16
            y: 16
            width: parent.width - 32
            height: parent.height - 32
            spacing: 12

            // ---------- header ----------
            Item {
                width: parent.width
                height: 26

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Settings"
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
                    onActivated: dialog.close()
                }
            }

            // ---------- body ----------
            Row {
                width: parent.width
                height: parent.height - 38
                spacing: 12

                // ----- tabs -----
                Column {
                    id: tabs
                    width: 150
                    height: parent.height
                    spacing: 4

                    TabButton {
                        theme: dialog.theme
                        label: "Pet"
                        active: dialog.tab === "pet"
                        onActivated: dialog.pickTab("pet")
                    }
                    TabButton {
                        theme: dialog.theme
                        label: "Sound & voice"
                        active: dialog.tab === "sound"
                        onActivated: dialog.pickTab("sound")
                    }
                    TabButton {
                        theme: dialog.theme
                        label: "Data"
                        active: dialog.tab === "data"
                        onActivated: dialog.pickTab("data")
                    }
                    TabButton {
                        theme: dialog.theme
                        label: "Model & account"
                        active: dialog.tab === "account"
                        onActivated: dialog.pickTab("account")
                    }

                    Text {
                        width: parent.width
                        text: "Stored in ~/.config/frieren/settings.json"
                        color: dialog.fgDim
                        opacity: 0.6
                        font.family: dialog.fontFamily
                        font.pixelSize: 9
                        wrapMode: Text.Wrap
                        topPadding: 8
                    }
                }

                Rectangle {
                    width: 1
                    height: parent.height
                    color: dialog.line
                    opacity: 0.6
                }

                // ----- content -----
                Flickable {
                    id: content
                    width: parent.width - 150 - 12 - 1 - 12
                    height: parent.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: pane.implicitHeight

                    Column {
                        id: pane
                        width: content.width
                        spacing: 12

                        // ----- Pet -----
                        Column {
                            width: parent.width
                            spacing: 10
                            visible: dialog.tab === "pet"

                            SectionTitle {
                                theme: dialog.theme
                                title: "Behavior"
                            }
                            ToggleRow {
                                theme: dialog.theme
                                label: "Wander"
                                description: "Roam the screen on her own"
                                checked: dialog.wanderEnabled
                                onActivated: dialog.toggleSetting("wander")
                            }
                            ToggleRow {
                                theme: dialog.theme
                                label: "Sleep when idle"
                                description: "Doze off after a while"
                                checked: dialog.sleepEnabled
                                onActivated: dialog.toggleSetting("sleep")
                            }
                            ToggleRow {
                                theme: dialog.theme
                                label: "Blink"
                                description: "Blink every few seconds"
                                checked: dialog.blinkEnabled
                                onActivated: dialog.toggleSetting("blink")
                            }

                            SectionTitle {
                                theme: dialog.theme
                                title: "Size"
                            }
                            Row {
                                width: parent.width
                                spacing: 8

                                ChoiceButton {
                                    theme: dialog.theme
                                    label: "Small"
                                    active: dialog.petScale <= 0.92
                                    onActivated: dialog.scaleSelected(0.85)
                                }
                                ChoiceButton {
                                    theme: dialog.theme
                                    label: "Medium"
                                    active: dialog.petScale > 0.92 && dialog.petScale < 1.08
                                    onActivated: dialog.scaleSelected(1.0)
                                }
                                ChoiceButton {
                                    theme: dialog.theme
                                    label: "Large"
                                    active: dialog.petScale >= 1.08
                                    onActivated: dialog.scaleSelected(1.15)
                                }
                            }

                            SectionTitle {
                                theme: dialog.theme
                                title: "Position"
                            }
                            ActionButton {
                                theme: dialog.theme
                                label: "Reset position"
                                onActivated: dialog.resetPosition()
                            }
                        }

                        // ----- Sound and voice -----
                        Column {
                            width: parent.width
                            spacing: 10
                            visible: dialog.tab === "sound"

                            SectionTitle {
                                theme: dialog.theme
                                title: "Sound"
                            }
                            ToggleRow {
                                theme: dialog.theme
                                label: "UI sounds"
                                description: "Pops and ticks on her actions"
                                checked: dialog.soundEnabled
                                onActivated: dialog.toggleSetting("sound")
                            }
                            ToggleRow {
                                theme: dialog.theme
                                label: "Voice replies"
                                description: "Speak answers aloud with Piper"
                                checked: dialog.voiceSpeak
                                onActivated: dialog.toggleSetting("voice")
                            }

                            SectionTitle {
                                theme: dialog.theme
                                title: "Voice"
                            }
                            Text {
                                width: parent.width
                                visible: dialog.voicesLoading
                                text: "Loading voices..."
                                color: dialog.fgDim
                                font.family: dialog.fontFamily
                                font.pixelSize: 11
                            }
                            Column {
                                width: parent.width
                                spacing: 2
                                visible: !dialog.voicesLoading

                                Repeater {
                                    model: dialog.voices

                                    RadioRow {
                                        theme: dialog.theme
                                        label: modelData
                                        active: modelData === dialog.voiceId
                                        onActivated: dialog.pickVoice(modelData)
                                    }
                                }
                            }
                            Text {
                                width: parent.width
                                visible: !dialog.voicesLoading && dialog.voices.length === 0
                                text: "No voices yet. Run: frieren-voice list"
                                color: dialog.fgDim
                                font.family: dialog.fontFamily
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }

                            SectionTitle {
                                theme: dialog.theme
                                title: "Volume"
                            }
                            Row {
                                width: parent.width
                                spacing: 8

                                ChoiceButton {
                                    theme: dialog.theme
                                    label: "Low"
                                    active: dialog.voiceVolume === 40
                                    onActivated: dialog.volumeSelected(40)
                                }
                                ChoiceButton {
                                    theme: dialog.theme
                                    label: "Medium"
                                    active: dialog.voiceVolume === 80
                                    onActivated: dialog.volumeSelected(80)
                                }
                                ChoiceButton {
                                    theme: dialog.theme
                                    label: "Loud"
                                    active: dialog.voiceVolume === 100
                                    onActivated: dialog.volumeSelected(100)
                                }
                                ChoiceButton {
                                    theme: dialog.theme
                                    label: "Max"
                                    active: dialog.voiceVolume === 130
                                    onActivated: dialog.volumeSelected(130)
                                }
                            }
                            ActionButton {
                                theme: dialog.theme
                                label: "Test voice"
                                onActivated: dialog.testVoice()
                            }
                        }

                        // ----- Data -----
                        Column {
                            width: parent.width
                            spacing: 10
                            visible: dialog.tab === "data"

                            SectionTitle {
                                theme: dialog.theme
                                title: "Activity"
                            }
                            ToggleRow {
                                theme: dialog.theme
                                label: "Activity log"
                                description: "Log turns and tool calls to frieren.db"
                                checked: dialog.logEnabled
                                onActivated: dialog.toggleSetting("log")
                            }
                            ToggleRow {
                                theme: dialog.theme
                                label: "Discord alerts"
                                description: "Post turn summaries to a webhook"
                                checked: dialog.discordEnabled
                                onActivated: dialog.toggleSetting("discord")
                            }
                            ActionButton {
                                theme: dialog.theme
                                label: "Send test embed"
                                onActivated: dialog.testDiscord()
                            }

                            SectionTitle {
                                theme: dialog.theme
                                title: "Backup"
                            }
                            Text {
                                width: parent.width
                                text: "Hot-copy frieren.db into the backups dir (prunes to 10)."
                                color: dialog.fgDim
                                font.family: dialog.fontFamily
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }
                            ActionButton {
                                theme: dialog.theme
                                label: "Backup database now"
                                onActivated: dialog.runBackup()
                            }
                        }

                        // ----- Model and account -----
                        Column {
                            width: parent.width
                            spacing: 10
                            visible: dialog.tab === "account"

                            AuthDialog {
                                theme: dialog.theme
                                visible: dialog.tab === "account"
                                provider: dialog.authProvider
                                model: dialog.modelName
                                models: dialog.models
                                modelsLoading: dialog.modelsLoading
                                status: dialog.authStatus
                                detail: dialog.authDetail
                                message: dialog.authMessage
                                messageOk: dialog.authMessageOk
                                messageError: dialog.authMessageError
                                checking: dialog.authChecking
                                busy: dialog.authBusy
                                width: parent.width
                                height: implicitHeight

                                onSaveKey: key => dialog.saveKey(key)
                                onTerminalLogin: dialog.terminalLogin()
                                onCheck: dialog.checkAuth()
                                onSaveModel: id => dialog.saveModel(id)
                                onClose: dialog.close()
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- reusable bits ----------
    component IconButton: Rectangle {
        id: iconBtn

        property var theme
        property string glyph: ""
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

    component TabButton: Rectangle {
        id: tabBtn

        property var theme
        property string label: ""
        property bool active: false
        signal activated()

        width: 150
        height: 34
        radius: 10
        color: tabBtn.active
            ? (theme ? theme.primaryContainer : "#4f378b")
            : (hover.containsMouse ? (theme ? theme.surfaceHigh : "#2b292f") : "transparent")

        Text {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 24
            text: tabBtn.label
            color: tabBtn.active
                ? (theme ? theme.primaryContainerText : "#e6e0e9")
                : (theme ? theme.textDim : "#cac4cf")
            font.family: theme ? theme.fontFamily : "sans-serif"
            font.pixelSize: 12
            font.weight: tabBtn.active ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tabBtn.activated()
        }
    }

    component SectionTitle: Text {
        property var theme
        property string title: ""

        width: parent.width
        text: title
        color: theme ? theme.textDim : "#cac4cf"
        opacity: 0.75
        font.family: theme ? theme.fontFamily : "sans-serif"
        font.pixelSize: 10
        font.weight: Font.DemiBold
    }

    component ToggleRow: Item {
        id: toggle

        property var theme
        property string label: ""
        property string description: ""
        property bool checked: false
        signal activated()

        width: parent.width
        height: Math.max(34, textColumn.height)

        Column {
            id: textColumn
            anchors.left: parent.left
            anchors.right: box.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: toggle.label
                color: theme ? theme.text : "#e6e0e9"
                font.family: theme ? theme.fontFamily : "sans-serif"
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: toggle.description.length > 0
                text: toggle.description
                color: theme ? theme.textDim : "#cac4cf"
                opacity: 0.8
                font.family: theme ? theme.fontFamily : "sans-serif"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: box
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 6
            color: toggle.checked ? (theme ? theme.accent : "#d0bcff") : "transparent"
            border.color: toggle.checked ? "transparent" : (theme ? theme.outline : "#49454e")
            border.width: 1

            Text {
                anchors.centerIn: parent
                visible: toggle.checked
                text: "✓"
                color: theme ? theme.accentText : "#381e72"
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: toggle.activated()
            }
        }

        MouseArea {
            anchors.left: parent.left
            anchors.right: box.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.activated()
        }
    }

    component RadioRow: Item {
        id: radio

        property var theme
        property string label: ""
        property bool active: false
        signal activated()

        width: parent.width
        height: 30

        Rectangle {
            id: dot
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: "transparent"
            border.color: radio.active ? (theme ? theme.accent : "#d0bcff") : (theme ? theme.outline : "#49454e")
            border.width: radio.active ? 2 : 1

            Rectangle {
                anchors.centerIn: parent
                visible: radio.active
                width: 8
                height: 8
                radius: 4
                color: theme ? theme.accent : "#d0bcff"
            }
        }

        Text {
            anchors.left: dot.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: radio.label
            color: radio.active ? (theme ? theme.text : "#e6e0e9") : (theme ? theme.textDim : "#cac4cf")
            font.family: theme ? theme.fontFamily : "sans-serif"
            font.pixelSize: 12
            elide: Text.ElideRight
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: radio.activated()
        }
    }

    component ChoiceButton: Rectangle {
        id: choiceBtn

        property var theme
        property string label: ""
        property bool active: false
        signal activated()

        width: choiceText.implicitWidth + 24
        height: 32
        radius: 9
        color: choiceBtn.active
            ? (theme ? theme.accent : "#d0bcff")
            : (hover.containsMouse ? (theme ? theme.surfaceHigh : "#2b292f") : "transparent")
        border.color: choiceBtn.active ? "transparent" : (theme ? theme.outline : "#49454e")
        border.width: choiceBtn.active ? 0 : 1

        Text {
            id: choiceText
            anchors.centerIn: parent
            text: choiceBtn.label
            color: choiceBtn.active
                ? (theme ? theme.accentText : "#381e72")
                : (theme ? theme.text : "#e6e0e9")
            font.family: theme ? theme.fontFamily : "sans-serif"
            font.pixelSize: 11
            font.weight: choiceBtn.active ? Font.DemiBold : Font.Normal
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: choiceBtn.activated()
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
        color: actionBtn.primary
            ? (theme ? theme.accent : "#d0bcff")
            : (hover.containsMouse ? (theme ? theme.surfaceHigh : "#2b292f") : "transparent")
        border.color: actionBtn.primary ? "transparent" : (theme ? theme.outline : "#49454e")
        border.width: actionBtn.primary ? 0 : 1

        Text {
            id: actionText
            anchors.centerIn: parent
            text: actionBtn.label
            color: actionBtn.primary
                ? (theme ? theme.accentText : "#381e72")
                : (theme ? theme.text : "#e6e0e9")
            font.family: theme ? theme.fontFamily : "sans-serif"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: actionBtn.activated()
        }
    }
}
