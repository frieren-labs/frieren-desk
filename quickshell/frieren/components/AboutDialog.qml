import QtQuick
import Quickshell

Item {
    id: dialog

    property var theme
    property string handle: "jd-apprentice"
    property string profileUrl: "https://github.com/jd-apprentice"
    property string repoUrl: "https://github.com/jd-apprentice/frieren-desk"
    property string licenseName: "MIT License"
    property string licenseUrl: "https://github.com/jd-apprentice/frieren-desk/blob/main/LICENSE"

    signal close()

    readonly property string fontFamily: theme ? theme.fontFamily : "sans-serif"
    readonly property color fg: theme ? theme.text : "#e6e0e9"
    readonly property color fgDim: theme ? theme.textDim : "#cac4cf"
    readonly property color accent: theme ? theme.accent : "#d0bcff"
    readonly property color surface: theme ? theme.surface : "#211f24"
    readonly property color surfaceHigh: theme ? theme.surfaceHigh : "#2b292f"
    readonly property color line: theme ? theme.outline : "#49454e"

    implicitWidth: 400
    implicitHeight: card.height

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
                height: 26

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "About"
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

            // ---------- happy Frieren ----------
            Rectangle {
                width: parent.width
                height: 150
                radius: 14
                color: dialog.surfaceHigh
                border.color: dialog.line
                border.width: 1

                Image {
                    anchors.centerIn: parent
                    width: 124
                    height: 138
                    source: "file://" + (Quickshell.env("HOME") || "")
                        + "/.config/quickshell/frieren/assets/poses/happy.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: false
                    sourceSize: Qt.size(248, 276)
                }
            }

            // ---------- project ----------
            Column {
                width: parent.width
                spacing: 3

                Text {
                    width: parent.width
                    text: "Frieren Desk"
                    color: dialog.fg
                    font.family: dialog.fontFamily
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    text: "A chibi Frieren desktop pet for Hyprland that talks to opencode and can change the system."
                    color: dialog.fgDim
                    font.family: dialog.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    lineHeight: 1.2
                }
            }

            // ---------- author ----------
            Row {
                width: parent.width
                spacing: 5

                Text {
                    text: "Made by"
                    color: dialog.fgDim
                    font.family: dialog.fontFamily
                    font.pixelSize: 11
                }

                Text {
                    id: authorHandle
                    text: "@" + dialog.handle
                    color: dialog.accent
                    font.family: dialog.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.underline: authorHover.containsMouse

                    MouseArea {
                        id: authorHover
                        anchors.fill: parent
                        anchors.margins: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(dialog.profileUrl)
                    }
                }
            }

            // ---------- links ----------
            Column {
                width: parent.width
                spacing: 6

                Text {
                    text: "Repository"
                    color: dialog.fgDim
                    opacity: 0.75
                    font.family: dialog.fontFamily
                    font.pixelSize: 9
                }

                LinkRow {
                    theme: dialog.theme
                    label: dialog.repoUrl
                    url: dialog.repoUrl
                }

                Text {
                    text: "License"
                    color: dialog.fgDim
                    opacity: 0.75
                    font.family: dialog.fontFamily
                    font.pixelSize: 9
                    topPadding: 2
                }

                Row {
                    spacing: 6

                    Text {
                        text: dialog.licenseName
                        color: dialog.fg
                        font.family: dialog.fontFamily
                        font.pixelSize: 11
                    }

                    Text {
                        text: "· Copyright (c) 2026 @" + dialog.handle
                        color: dialog.fgDim
                        font.family: dialog.fontFamily
                        font.pixelSize: 10
                    }
                }

                LinkRow {
                    theme: dialog.theme
                    label: "Read the license"
                    url: dialog.licenseUrl
                }
            }

            // ---------- footer ----------
            Text {
                width: parent.width
                text: "Fan art. Frieren belongs to Kanehito Yamada and Tsukasa Abe."
                color: dialog.fgDim
                opacity: 0.6
                font.family: dialog.fontFamily
                font.pixelSize: 9
                wrapMode: Text.Wrap
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

    component LinkRow: Item {
        id: link

        property var theme
        property string label: ""
        property string url: ""

        width: parent.width
        height: linkText.implicitHeight

        Text {
            id: linkText
            width: parent.width
            text: link.label
            color: link.theme ? link.theme.accent : "#d0bcff"
            font.family: link.theme ? link.theme.fontFamily : "sans-serif"
            font.pixelSize: 11
            elide: Text.ElideRight
            font.underline: hover.containsMouse
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(link.url)
        }
    }
}
