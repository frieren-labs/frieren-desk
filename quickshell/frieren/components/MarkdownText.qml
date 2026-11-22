import QtQuick

// A small Markdown renderer for chat messages.
//
// Qt has no Markdown document, so this splits the text into fenced code blocks
// and prose lines, then renders the prose with Qt's rich text subset. Code
// blocks get their own box, monospace font and a copy button. All text is
// selectable with the mouse.
Item {
    id: md

    property var theme
    property string text: ""

    readonly property string fontFamily: theme ? theme.fontFamily : "sans-serif"
    readonly property string monoFamily: theme ? theme.monoFamily : "monospace"
    readonly property color fg: theme ? theme.text : "#e6e0e9"
    readonly property color fgDim: theme ? theme.textDim : "#cac4cf"
    readonly property color codeColor: theme ? theme.accent : "#d0bcff"
    readonly property color surfaceHigh: theme ? theme.surfaceHigh : "#2b292f"
    readonly property color line: theme ? theme.outline : "#49454e"
    readonly property color selectionColor: theme ? theme.primaryContainer : "#4f378b"
    readonly property color selectionText: theme ? theme.primaryContainerText : "#e6e0e9"

    readonly property var blocks: md.parse(text)

    implicitHeight: col.height

    // ---------------- parsing ----------------

    function escapeHtml(value) {
        return String(value)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    }

    function inline(raw) {
        let s = escapeHtml(raw);
        const codes = [];
        s = s.replace(/`([^`]+)`/g, function (m, code) {
            codes.push(code);
            return "\u0000" + (codes.length - 1) + "\u0000";
        });
        s = s.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
        s = s.replace(/__([^_]+)__/g, "<b>$1</b>");
        s = s.replace(/(^|[^\w*])\*([^*\n]+)\*(?!\w)/g, "$1<i>$2</i>");
        s = s.replace(/(^|[^\w])_([^_\n]+)_(?!\w)/g, "$1<i>$2</i>");
        s = s.replace(/~~([^~]+)~~/g, "<s>$1</s>");
        s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g,
            '<a href="$2" style="color:' + String(md.codeColor) + ';">$1</a>');

        const family = String(md.monoFamily).replace(/["']/g, "");
        const codeStyle = 'font-family:\'' + family + '\'; color:' + String(md.codeColor);
        s = s.replace(/\u0000(\d+)\u0000/g, function (m, index) {
            return '<span style="' + codeStyle + '">' + codes[Number(index)] + '</span>';
        });
        return s;
    }

    function isFence(line) {
        return /^\s{0,3}(`{3,}|~{3,})/.test(line);
    }

    function isRule(line) {
        return /^\s{0,3}([-*_])(\s*\1){2,}\s*$/.test(line);
    }

    function parse(source) {
        const lines = String(source || "").replace(/\r\n/g, "\n").split("\n");
        const out = [];
        let i = 0;

        while (i < lines.length) {
            const line = lines[i];
            const fence = line.match(/^\s{0,3}(`{3,}|~{3,})(.*)$/);

            if (fence) {
                const marker = fence[1];
                const lang = fence[2].trim().split(/\s+/)[0] || "";
                const body = [];
                i += 1;
                while (i < lines.length) {
                    const close = lines[i].match(/^\s{0,3}(`{3,}|~{3,})\s*$/);
                    if (close && close[1][0] === marker[0] && close[1].length >= marker.length) {
                        i += 1;
                        break;
                    }
                    body.push(lines[i]);
                    i += 1;
                }
                out.push({ kind: "code", lang: lang, code: body.join("\n") });
                continue;
            }

            if (line.trim().length === 0) {
                i += 1;
                continue;
            }

            if (isRule(line)) {
                out.push({ kind: "prose", style: "hr", text: "" });
                i += 1;
                continue;
            }

            const heading = line.match(/^\s{0,3}(#{1,6})\s+(.*)$/);
            if (heading) {
                out.push({
                    kind: "prose",
                    style: "h" + heading[1].length,
                    text: heading[2].replace(/\s+#+\s*$/, "").trim()
                });
                i += 1;
                continue;
            }

            const quote = line.match(/^\s{0,3}>\s?(.*)$/);
            if (quote) {
                out.push({ kind: "prose", style: "quote", text: quote[1] });
                i += 1;
                continue;
            }

            const bullet = line.match(/^(\s*)[-*+]\s+(.*)$/);
            if (bullet) {
                out.push({
                    kind: "prose",
                    style: "bullet",
                    text: bullet[2],
                    level: Math.min(2, Math.floor(bullet[1].length / 2))
                });
                i += 1;
                continue;
            }

            const ordered = line.match(/^(\s*)(\d{1,3})[.)]\s+(.*)$/);
            if (ordered) {
                out.push({
                    kind: "prose",
                    style: "number",
                    text: ordered[3],
                    marker: ordered[2] + ".",
                    level: Math.min(2, Math.floor(ordered[1].length / 2))
                });
                i += 1;
                continue;
            }

            const buf = [line.trim()];
            i += 1;
            while (i < lines.length) {
                const next = lines[i];
                if (next.trim().length === 0) break;
                if (isFence(next) || isRule(next)) break;
                if (/^\s{0,3}#{1,6}\s+/.test(next)) break;
                if (/^\s{0,3}>\s?/.test(next)) break;
                if (/^\s*[-*+]\s+/.test(next)) break;
                if (/^\s*\d{1,3}[.)]\s+/.test(next)) break;
                buf.push(next.trim());
                i += 1;
            }
            out.push({ kind: "prose", style: "p", text: buf.join(" ") });
        }

        return out;
    }

    function pixelSize(style) {
        if (style === "h1") return 16;
        if (style === "h2") return 15;
        if (style === "h3") return 14;
        if (style === "h4" || style === "h5" || style === "h6") return 13;
        return 13;
    }

    function weightFor(style) {
        if (style === "h1" || style === "h2" || style === "h3") return Font.Bold;
        if (style === "h4" || style === "h5" || style === "h6") return Font.DemiBold;
        return Font.Normal;
    }

    Column {
        id: col
        width: parent.width
        spacing: 8

        Repeater {
            model: md.blocks

            delegate: Item {
                id: block

                readonly property var entry: modelData
                readonly property bool isCode: entry && entry.kind === "code"
                readonly property string entryStyle: entry && !isCode ? entry.style : ""
                readonly property bool isRule: entryStyle === "hr"
                readonly property bool isList: entryStyle === "bullet" || entryStyle === "number"
                readonly property bool isQuote: entryStyle === "quote"

                width: col.width
                height: isCode ? codeBox.height
                    : isRule ? 9
                    : isList ? listText.contentHeight
                    : proseText.contentHeight

                // ---- fenced code ----
                Rectangle {
                    id: codeBox
                    visible: block.isCode
                    width: parent.width
                    height: codeCol.height + 16
                    radius: 8
                    color: md.surfaceHigh
                    border.color: md.line
                    border.width: 1

                    Column {
                        id: codeCol
                        x: 10
                        y: 8
                        width: parent.width - 20
                        spacing: 2

                        Item {
                            width: parent.width
                            height: 20

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: block.entry && block.entry.lang ? block.entry.lang : "code"
                                color: md.fgDim
                                opacity: 0.7
                                font.family: md.monoFamily
                                font.pixelSize: 9
                            }

                            CopyButton {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                theme: md.theme
                                text: block.entry && block.entry.code ? block.entry.code : ""
                                tooltip: "Copy code"
                            }
                        }

                        TextEdit {
                            width: parent.width
                            height: contentHeight
                            text: block.entry && block.entry.code ? block.entry.code : ""
                            color: md.fg
                            textFormat: TextEdit.PlainText
                            wrapMode: TextEdit.WrapAnywhere
                            readOnly: true
                            selectByMouse: true
                            persistentSelection: true
                            cursorVisible: false
                            selectionColor: md.selectionColor
                            selectedTextColor: md.selectionText
                            font.family: md.monoFamily
                            font.pixelSize: 11
                        }
                    }
                }

                // ---- blockquote bar ----
                Rectangle {
                    visible: block.isQuote
                    width: 2
                    height: block.height
                    radius: 1
                    color: md.codeColor
                    opacity: 0.55
                }

                // ---- plain prose ----
                TextEdit {
                    id: proseText
                    visible: !block.isCode && !block.isList && !block.isRule
                    x: block.isQuote ? 10 : 0
                    width: parent.width - x
                    height: contentHeight
                    text: block.isCode || block.isRule ? "" : md.inline(block.entry ? block.entry.text : "")
                    textFormat: TextEdit.RichText
                    wrapMode: TextEdit.Wrap
                    readOnly: true
                    selectByMouse: true
                    persistentSelection: true
                    cursorVisible: false
                    color: block.isQuote ? md.fgDim : md.fg
                    selectionColor: md.selectionColor
                    selectedTextColor: md.selectionText
                    font.family: md.fontFamily
                    font.pixelSize: md.pixelSize(block.entryStyle)
                    font.weight: md.weightFor(block.entryStyle)
                    font.italic: block.isQuote
                }

                // ---- list item ----
                Row {
                    id: listRow
                    visible: block.isList
                    x: 2 + (block.entry && block.entry.level ? block.entry.level * 14 : 0)
                    width: parent.width - x
                    spacing: 6

                    Text {
                        width: 18
                        text: block.entry && block.entry.style === "number"
                            ? block.entry.marker : "•"
                        color: md.fgDim
                        horizontalAlignment: Text.AlignRight
                        font.family: md.fontFamily
                        font.pixelSize: 13
                        lineHeight: 1.25
                    }

                    TextEdit {
                        id: listText
                        width: listRow.width - 24
                        height: contentHeight
                        text: block.isList && block.entry ? md.inline(block.entry.text || "") : ""
                        textFormat: TextEdit.RichText
                        wrapMode: TextEdit.Wrap
                        readOnly: true
                        selectByMouse: true
                        persistentSelection: true
                        cursorVisible: false
                        color: md.fg
                        selectionColor: md.selectionColor
                        selectedTextColor: md.selectionText
                        font.family: md.fontFamily
                        font.pixelSize: 13
                    }
                }

                // ---- horizontal rule ----
                Rectangle {
                    visible: block.isRule
                    width: parent.width
                    height: 1
                    color: md.line
                    opacity: 0.6
                }
            }
        }
    }
}
