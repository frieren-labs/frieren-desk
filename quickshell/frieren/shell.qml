import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "components"

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string opencodeBin: home + "/.opencode/bin/opencode"
    readonly property string agentName: "frieren"
    readonly property string modelName: "opencode-go/deepseek-v4.1-flash"
    readonly property string authProvider: modelName.split("/")[0]
    readonly property bool authMissing: authStatus === "missing"
    readonly property string terminalLauncher: [
        "for term in xdg-terminal-exec foot kitty alacritty ghostty wezterm konsole gnome-terminal xterm; do",
        "  command -v \"$term\" >/dev/null 2>&1 || continue",
        "  case \"$term\" in",
        "    xdg-terminal-exec|foot|kitty) exec \"$term\" \"$0\" auth login \"$1\" ;;",
        "    alacritty|ghostty|konsole|xterm) exec \"$term\" -e \"$0\" auth login \"$1\" ;;",
        "    wezterm) exec \"$term\" start -- \"$0\" auth login \"$1\" ;;",
        "    gnome-terminal) exec \"$term\" -- \"$0\" auth login \"$1\" ;;",
        "  esac",
        "done",
        "exit 127"
    ].join("\n")

    // OpenCode account state. A bool copy goes to state.json for the tray menu.
    property string authStatus: "unknown" // unknown | connected | missing | error
    property string authDetail: ""
    property string authMessage: ""
    property bool authMessageOk: false
    property bool authMessageError: false
    property bool authChecking: false
    property bool authSaving: false
    property bool authOpen: false
    property bool aboutOpen: false
    property bool stateLoaded: false
    property var authCredentials: []
    property var authCleanupIds: []
    property string authNewCredential: ""
    property string authFailMessage: ""
    property string authQueuedKey: ""

    property bool chatOpen: false
    property bool busy: false
    property bool toolActive: false
    property bool stopping: false
    property int toolCount: 0
    property bool hasError: false

    // settings (persisted in state.json and exposed by the tray menu)
    property bool minimized: false
    property bool wanderEnabled: true
    property bool sleepEnabled: true
    property bool blinkEnabled: true
    property bool logEnabled: true
    property real petScale: 1.0
    property real lastGoodX: 80
    property real lastGoodY: 220

    // partID -> index in the ListModel
    property var partIndex: ({})

    // conversation history (SQLite, same file as the activity log)
    property var conversations: []
    property bool historyReady: false
    property bool historyStarted: false
    property bool legacyMigrating: false
    property bool chatRestored: false
    property string activeConvId: ""
    property var historyLoadQueue: []

    // per-turn telemetry (fed to the activity hook)
    property string turnPrompt: ""
    property real turnStarted: 0
    property int turnTools: 0
    property int turnToolFails: 0
    property string turnError: ""
    property bool turnLogged: false
    property var toolStartTimes: ({})
    property var toolFinished: ({})

    // ---------------- theme (matugen/DMS, with fallback) ----------------
    QtObject {
        id: theme

        property string fontFamily: "Google Sans Flex"
        property string monoFamily: "FiraCode Nerd Font"

        property color background: "#141218"
        property color surface: "#211f24"
        property color surfaceHigh: "#2b292f"
        property color text: "#e6e0e9"
        property color textDim: "#cac4cf"
        property color accent: "#d0bcff"
        property color accentText: "#381e72"
        property color primaryContainer: "#4f378b"
        property color primaryContainerText: "#e6e0e9"
        property color outline: "#49454e"
        property color danger: "#f2b8b5"
        property color ok: "#7fff9a"
    }

    FileView {
        path: root.home + "/.cache/dms/dms-colors.json"
        watchChanges: true
        onLoaded: root.applyDmsColors(text())
    }

    FileView {
        path: root.home + "/.cache/dms/dms-typography.json"
        watchChanges: true
        onLoaded: root.applyDmsType(text())
    }

    function applyDmsColors(raw) {
        try {
            const doc = JSON.parse(raw);
            const c = (doc.colors && (doc.colors[doc.mode] || doc.colors.dark)) || {};
            if (c.background) theme.background = c.background;
            if (c.surface_container) theme.surface = c.surface_container;
            if (c.surface_container_high) theme.surfaceHigh = c.surface_container_high;
            if (c.on_surface) theme.text = c.on_surface;
            if (c.on_surface_variant) theme.textDim = c.on_surface_variant;
            if (c.primary) theme.accent = c.primary;
            if (c.on_primary) theme.accentText = c.on_primary;
            if (c.primary_container) theme.primaryContainer = c.primary_container;
            if (c.on_primary_container) theme.primaryContainerText = c.on_primary_container;
            if (c.outline_variant) theme.outline = c.outline_variant;
            if (c.error) theme.danger = c.error;
        } catch (e) {
            // keep the fallback
        }
    }

    function applyDmsType(raw) {
        try {
            const doc = JSON.parse(raw);
            if (doc.fontFamily) theme.fontFamily = doc.fontFamily;
            if (doc.monoFontFamily) theme.monoFamily = doc.monoFontFamily;
        } catch (e) {}
    }

    // ---------------- persistent state (own file) ----------------
    readonly property string stateDir: home + "/.local/state/frieren"
    readonly property string statePath: stateDir + "/state.json"
    readonly property string dbPath: stateDir + "/frieren.db"
    readonly property string hookPath: home + "/.config/quickshell/frieren/hooks/frieren-log.sh"

    property real petX: 80
    property real petY: 220
    property string sessionId: ""

    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        onLoaded: root.loadState(text())
        onLoadFailed: {
            // No state file yet, or it cannot be read. Do not block the auth
            // flag from reaching the tray menu.
            root.stateLoaded = true;
            if (root.authStatus !== "unknown") root.saveState();
            root.restoreChatFromHistory();
        }
    }

    // A missing state file does not always emit loadFailed. Do not wait
    // forever to persist the account flag.
    Timer {
        interval: 2000
        running: true
        repeat: false
        onTriggered: {
            if (root.stateLoaded) return;
            root.stateLoaded = true;
            if (root.authStatus !== "unknown") root.saveState();
            root.restoreChatFromHistory();
        }
    }

    Process {
        id: stateWriter
        stdinEnabled: false
    }

    function loadState(raw) {
        // Changing petScale below triggers onPetScaleChanged. Mark the pet as
        // unplaced first so that handler does not save the stale default
        // position before the loaded position is applied.
        root.petPlaced = false;
        try {
            const doc = JSON.parse(raw);
            if (typeof doc.x === "number") root.petX = doc.x;
            if (typeof doc.y === "number") root.petY = doc.y;
            if (typeof doc.session === "string") root.sessionId = doc.session;
            if (typeof doc.minimized === "boolean") root.minimized = doc.minimized;
            if (typeof doc.wander === "boolean") root.wanderEnabled = doc.wander;
            if (typeof doc.sleep === "boolean") root.sleepEnabled = doc.sleep;
            if (typeof doc.blink === "boolean") root.blinkEnabled = doc.blink;
            if (typeof doc.log === "boolean") root.logEnabled = doc.log;
            if (typeof doc.scale === "number")
                root.petScale = Math.max(0.7, Math.min(1.4, doc.scale));
        } catch (e) {}

        root.lastGoodX = root.petX;
        root.lastGoodY = root.petY;
        if (root.petY < 60) {
            root.lastGoodX = 80;
            root.lastGoodY = 220;
        }

        root.placePet();
        root.stateLoaded = true;
        // The auth check can finish before the state file loads. Persist the
        // account flag now that the loaded values are in place.
        if (root.authStatus !== "unknown") root.saveState();
        root.restoreChatFromHistory();
    }

    property bool petPlaced: false

    function clampPet() {
        if (!pet || petWin.width < pet.width || petWin.height < pet.height) return;
        pet.x = Math.max(0, Math.min(pet.x, petWin.width - pet.width));
        pet.y = Math.max(0, Math.min(pet.y, petWin.height - pet.height));
    }

    // The surface starts at 500x500 and only later gets its real size:
    // clamping against that provisional size would be wrong.
    function placePet() {
        if (!pet || root.petPlaced) return;
        const sw = petWin.screen ? petWin.screen.width : 0;
        const sh = petWin.screen ? petWin.screen.height : 0;
        if (!sw || !sh) return;
        pet.x = Math.max(0, Math.min(root.petX, sw - pet.width));
        pet.y = Math.max(0, Math.min(root.petY, sh - pet.height));
        root.petPlaced = true;
    }

    function saveState() {
        const payload = JSON.stringify({
            x: Math.round(root.minimized ? root.petX : (pet ? pet.x : root.petX)),
            y: Math.round(root.minimized ? root.petY : (pet ? pet.y : root.petY)),
            session: root.sessionId,
            minimized: root.minimized,
            wander: root.wanderEnabled,
            sleep: root.sleepEnabled,
            blink: root.blinkEnabled,
            log: root.logEnabled,
            scale: root.petScale,
            auth: root.authStatus === "connected",
            busy: root.busy,
            chatOpen: root.chatOpen
        });
        stateWriter.command = [
            "sh", "-c",
            'mkdir -p "$0" && printf %s "$1" > "$0/state.json.tmp" && mv "$0/state.json.tmp" "$0/state.json"',
            root.stateDir, payload
        ];
        stateWriter.running = true;
    }

    function isNearBar() {
        if (!pet || petWin.height <= 0) return false;
        const bar = 44;
        return pet.y <= bar || pet.y + pet.height >= petWin.height - bar;
    }

    function minimizePet() {
        if (root.minimized) return;
        if (root.isNearBar()) {
            root.petX = root.lastGoodX;
            root.petY = root.lastGoodY;
        } else {
            root.petX = pet ? pet.x : root.petX;
            root.petY = pet ? pet.y : root.petY;
        }
        if (pet) {
            pet.x = root.petX;
            pet.y = root.petY;
        }
        root.minimized = true;
        root.chatOpen = false;
        root.saveState();
    }

    function restorePet() {
        root.minimized = false;
        root.petPlaced = false;
        root.placePet();
        root.saveState();
        if (pet) pet.wake();
    }

    onBusyChanged: root.saveState()
    onChatOpenChanged: root.saveState()
    onPetScaleChanged: {
        if (!root.petPlaced) return;
        // placePet() works from petX/petY, so capture the live position first.
        if (pet) {
            root.petX = pet.x;
            root.petY = pet.y;
        }
        root.petPlaced = false;
        root.placePet();
        if (root.petPlaced) root.saveState();
    }

    // ---------------- conversation ----------------
    ListModel {
        id: chat
    }

    function addMessage(role, text) {
        chat.append({
            role: role,
            text: text || "",
            command: "",
            output: "",
            status: "",
            ts: Date.now()
        });
        return chat.count - 1;
    }

    // ---------------- conversation history (SQLite) ----------------
    // History and the activity log share frieren.db. QML talks to it through
    // the sqlite3 CLI, and every payload travels over stdin, so long
    // conversations never hit the argv limit.
    readonly property string historySchema: [
        "CREATE TABLE IF NOT EXISTS conversations (",
        "  id TEXT PRIMARY KEY,",
        "  title TEXT NOT NULL DEFAULT '',",
        "  created_at INTEGER NOT NULL DEFAULT 0,",
        "  updated_at INTEGER NOT NULL DEFAULT 0",
        ");",
        "CREATE TABLE IF NOT EXISTS messages (",
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,",
        "  conversation_id TEXT NOT NULL,",
        "  role TEXT NOT NULL DEFAULT '',",
        "  text TEXT NOT NULL DEFAULT '',",
        "  command TEXT NOT NULL DEFAULT '',",
        "  output TEXT NOT NULL DEFAULT '',",
        "  status TEXT NOT NULL DEFAULT '',",
        "  ts INTEGER NOT NULL DEFAULT 0",
        ");",
        "CREATE INDEX IF NOT EXISTS messages_conversation ON messages(conversation_id);",
        "CREATE INDEX IF NOT EXISTS conversations_updated ON conversations(updated_at);"
    ].join("\n")

    Process {
        id: historyLister
        running: false
        stdinEnabled: true
        command: ["sqlite3", "-json", "-cmd", ".timeout 5000", root.dbPath]
        stdout: StdioCollector { id: historyListOut }
        onStarted: {
            historyLister.write(root.historySchema + "\n" + root.historyListSql());
            historyLister.stdinEnabled = false;
        }
        onExited: (code, status) => root.applyHistoryList(historyListOut.text)
    }

    Process {
        id: historyLoader
        property string conversationId: ""
        running: false
        stdinEnabled: true
        command: ["sqlite3", "-json", "-cmd", ".timeout 5000", root.dbPath]
        stdout: StdioCollector { id: historyLoadOut }
        onStarted: {
            historyLoader.write(root.historySchema + "\n"
                + root.historyMessagesSql(historyLoader.conversationId));
            historyLoader.stdinEnabled = false;
        }
        onExited: (code, status) => {
            const id = historyLoader.conversationId;
            historyLoader.conversationId = "";
            root.finishLoadConversation(id, historyLoadOut.text);
            root.flushHistoryLoads();
        }
    }

    Process {
        id: historyWriter
        property var queue: []
        property string sql: ""
        running: false
        stdinEnabled: true
        command: ["sqlite3", "-cmd", ".timeout 5000", root.dbPath]

        onStarted: {
            historyWriter.write(historyWriter.sql);
            historyWriter.sql = "";
            historyWriter.stdinEnabled = false;
        }

        onExited: (code, status) => {
            historyWriter.stdinEnabled = true;
            startNext();
            if (!running && queue.length === 0 && root.legacyMigrating) {
                root.legacyMigrating = false;
                if (code === 0) root.retireLegacyHistory();
                root.historyStarted = false;
                root.chatRestored = false;
                root.startHistory();
            }
        }

        function startNext() {
            if (running || queue.length === 0) return;
            sql = String(queue.shift());
            running = true;
        }
    }

    // The JSON file used before the database existed. It is imported once and
    // then renamed, so the migration cannot overwrite newer rows.
    FileView {
        id: legacyHistory
        path: root.stateDir + "/history.json"
        printErrors: false
        onLoaded: root.migrateLegacyHistory(text())
        onLoadFailed: root.startHistory()
    }

    Process {
        id: legacyRetire
        running: false
        command: ["sh", "-c", 'mv -f "$0" "$0.migrated"', root.stateDir + "/history.json"]
    }

    // A missing file does not always emit loadFailed. Do not wait forever.
    Timer {
        interval: 1200
        running: true
        repeat: false
        onTriggered: root.startHistory()
    }

    function startHistory() {
        if (root.historyStarted || root.legacyMigrating) return;
        root.historyStarted = true;
        historyLister.running = true;
    }

    function sqlLiteral(value) {
        return "'" + String(value).replace(/'/g, "''") + "'";
    }

    function historyListSql() {
        return "SELECT c.id, c.title, c.updated_at AS updated, "
            + "(SELECT count(*) FROM messages m WHERE m.conversation_id = c.id"
            + " AND m.role = 'user') AS questions "
            + "FROM conversations c ORDER BY c.updated_at DESC LIMIT 60;";
    }

    function historyMessagesSql(id) {
        return "SELECT role, text, command, output, status, ts FROM messages "
            + "WHERE conversation_id = " + root.sqlLiteral(id) + " ORDER BY id;";
    }

    function historyPruneSql() {
        return "DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations"
            + " WHERE id NOT IN (SELECT id FROM conversations ORDER BY updated_at DESC LIMIT 60));"
            + "\nDELETE FROM conversations WHERE id NOT IN"
            + " (SELECT id FROM conversations ORDER BY updated_at DESC LIMIT 60);";
    }

    function historySaveSql(id, title, updated, messages) {
        const json = root.sqlLiteral(JSON.stringify({
            id: id, title: title, updated: updated, messages: messages
        }));
        return root.historySchema
            + "\nBEGIN;"
            + "\nINSERT INTO conversations (id, title, created_at, updated_at)"
            + " VALUES (json_extract(" + json + ", '$.id'),"
            + " json_extract(" + json + ", '$.title'),"
            + " json_extract(" + json + ", '$.updated'),"
            + " json_extract(" + json + ", '$.updated'))"
            + " ON CONFLICT(id) DO UPDATE SET"
            + " title = excluded.title, updated_at = excluded.updated_at;"
            + "\nDELETE FROM messages WHERE conversation_id = json_extract(" + json + ", '$.id');"
            + "\nINSERT INTO messages (conversation_id, role, text, command, output, status, ts)"
            + " SELECT json_extract(" + json + ", '$.id'),"
            + " json_extract(value, '$.role'), json_extract(value, '$.text'),"
            + " json_extract(value, '$.command'), json_extract(value, '$.output'),"
            + " json_extract(value, '$.status'), json_extract(value, '$.ts')"
            + " FROM json_each(json_extract(" + json + ", '$.messages'));"
            + "\n" + root.historyPruneSql()
            + "\nCOMMIT;";
    }

    function historyDeleteSql(id) {
        const key = root.sqlLiteral(id);
        return root.historySchema
            + "\nDELETE FROM messages WHERE conversation_id = " + key + ";"
            + "\nDELETE FROM conversations WHERE id = " + key + ";";
    }

    function queueHistoryWrite(sql) {
        historyWriter.queue.push(sql);
        historyWriter.startNext();
    }

    function applyHistoryList(raw) {
        let rows = [];
        try {
            rows = JSON.parse(String(raw || "[]"));
        } catch (e) {}
        if (!Array.isArray(rows)) rows = [];
        root.conversations = rows.map(row => ({
            id: String(row.id || ""),
            title: String(row.title || ""),
            updated: Number(row.updated) || 0,
            questions: Number(row.questions) || 0
        })).filter(conv => conv.id.length > 0);
        root.historyReady = true;
        root.restoreChatFromHistory();
    }

    function migrateLegacyHistory(raw) {
        let doc = null;
        try {
            doc = JSON.parse(raw);
        } catch (e) {}
        if (!doc || !Array.isArray(doc.conversations) || doc.conversations.length === 0) {
            root.retireLegacyHistory();
            root.startHistory();
            return;
        }
        const convs = doc.conversations.filter(conv =>
            conv && typeof conv.id === "string" && Array.isArray(conv.messages));
        if (convs.length === 0) {
            root.retireLegacyHistory();
            root.startHistory();
            return;
        }
        const json = root.sqlLiteral(JSON.stringify(convs.map(conv => ({
            id: String(conv.id),
            title: String(conv.title || ""),
            updated: Number(conv.updated) || Date.now(),
            messages: conv.messages.map(m => ({
                role: String((m && m.role) || "assistant"),
                text: String((m && m.text) || ""),
                command: String((m && m.command) || ""),
                output: String((m && m.output) || ""),
                status: String((m && m.status) || ""),
                ts: Number((m && m.ts) || 0)
            }))
        }))));
        root.legacyMigrating = true;
        root.queueHistoryWrite(root.historySchema
            + "\nBEGIN;"
            + "\nDELETE FROM messages WHERE conversation_id IN"
            + " (SELECT json_extract(value, '$.id') FROM json_each(" + json + "));"
            + "\nDELETE FROM conversations WHERE id IN"
            + " (SELECT json_extract(value, '$.id') FROM json_each(" + json + "));"
            + "\nINSERT INTO conversations (id, title, created_at, updated_at)"
            + " SELECT json_extract(value, '$.id'), json_extract(value, '$.title'),"
            + " json_extract(value, '$.updated'), json_extract(value, '$.updated')"
            + " FROM json_each(" + json + ");"
            + "\nINSERT INTO messages (conversation_id, role, text, command, output, status, ts)"
            + " SELECT json_extract(c.value, '$.id'), json_extract(m.value, '$.role'),"
            + " json_extract(m.value, '$.text'), json_extract(m.value, '$.command'),"
            + " json_extract(m.value, '$.output'), json_extract(m.value, '$.status'),"
            + " json_extract(m.value, '$.ts')"
            + " FROM json_each(" + json + ") AS c,"
            + " json_each(json_extract(c.value, '$.messages')) AS m;"
            + "\n" + root.historyPruneSql()
            + "\nCOMMIT;");
    }

    function retireLegacyHistory() {
        if (!legacyRetire.running) legacyRetire.running = true;
    }

    function restoreChatFromHistory() {
        if (root.chatRestored || !root.stateLoaded || !root.historyReady) return;
        root.chatRestored = true;
        if (chat.count > 0) return;
        if (root.conversations.length === 0) return;
        // Only reopen the conversation of the saved opencode session. A fresh
        // conversation has no session id and starts empty on purpose.
        if (root.sessionId.length === 0) return;

        for (let i = 0; i < root.conversations.length; i += 1) {
            if (root.conversations[i].id === root.sessionId) {
                root.requestConversation(root.sessionId);
                return;
            }
        }
    }

    function isDraftId(id) {
        return String(id || "").indexOf("local-") === 0;
    }

    function requestConversation(id) {
        if (root.historyLoadQueue.indexOf(id) >= 0) return;
        if (historyLoader.running) {
            root.historyLoadQueue.push(id);
            return;
        }
        historyLoader.conversationId = id;
        historyLoader.running = true;
    }

    function flushHistoryLoads() {
        if (historyLoader.running || root.historyLoadQueue.length === 0) return;
        root.requestConversation(String(root.historyLoadQueue.shift()));
    }

    function finishLoadConversation(id, raw) {
        let rows = [];
        try {
            rows = JSON.parse(String(raw || "[]"));
        } catch (e) {}
        if (!Array.isArray(rows) || rows.length === 0 || id.length === 0) return;

        chat.clear();
        root.partIndex = ({});
        for (let i = 0; i < rows.length; i += 1) {
            const m = rows[i] || {};
            chat.append({
                role: String(m.role || "assistant"),
                text: String(m.text || ""),
                command: String(m.command || ""),
                output: String(m.output || ""),
                status: String(m.status || ""),
                ts: Number(m.ts) || 0
            });
        }
        root.activeConvId = id;
        root.sessionId = root.isDraftId(id) ? "" : id;
        root.saveState();
        pet.wake();
    }

    function openConversation(id) {
        if (root.busy) {
            root.addMessage("system", "Wait for the current request to finish before switching conversations.");
            return;
        }
        if (chat.count > 0 && id === root.activeConvId) {
            pet.wake();
            return;
        }
        for (let i = 0; i < root.conversations.length; i += 1) {
            if (root.conversations[i].id === id) {
                root.requestConversation(id);
                return;
            }
        }
    }

    function deleteConversation(id) {
        root.conversations = root.conversations.filter(conv => conv.id !== id);
        const active = id === root.sessionId
            || (root.activeConvId.length > 0 && id === root.activeConvId);
        if (active) {
            root.sessionId = "";
            root.activeConvId = "";
            chat.clear();
            root.partIndex = ({});
            root.saveState();
            root.addMessage("assistant", "Conversation deleted. What do you need?");
        }
        root.queueHistoryWrite(root.historyDeleteSql(id));
    }

    function conversationSnapshot() {
        const messages = [];
        for (let i = 0; i < chat.count; i += 1) {
            const m = chat.get(i);
            if (m.role === "system" && !m.text) continue;
            messages.push({
                role: String(m.role),
                text: String(m.text || ""),
                command: String(m.command || ""),
                output: String(m.output || "").slice(0, 1500),
                status: String(m.status || ""),
                ts: m.ts || 0
            });
        }
        return messages;
    }

    function historyTitle(messages) {
        for (let i = 0; i < messages.length; i += 1) {
            if (messages[i].role !== "user") continue;
            const text = messages[i].text.replace(/\s+/g, " ").trim();
            if (text.length > 0) return text.slice(0, 70);
        }
        return "";
    }

    function saveHistory() {
        if (!root.historyReady) return;
        const messages = root.conversationSnapshot();
        const title = root.historyTitle(messages);
        // Greetings and notices alone are not a conversation worth keeping.
        if (title.length === 0) return;

        if (root.activeConvId.length === 0)
            root.activeConvId = root.sessionId.length > 0 ? root.sessionId : ("local-" + Date.now());

        const id = root.activeConvId;
        const updated = Date.now();
        const kept = messages.slice(-150);
        let questions = 0;
        for (let i = 0; i < kept.length; i += 1) {
            if (kept[i].role === "user") questions += 1;
        }

        const entry = {
            id: id,
            title: title,
            updated: updated,
            questions: questions
        };
        const list = root.conversations.slice();
        let index = -1;
        for (let i = 0; i < list.length; i += 1) {
            if (list[i].id === id) {
                index = i;
                break;
            }
        }
        if (index >= 0) list[index] = entry;
        else list.push(entry);
        list.sort((a, b) => (b.updated || 0) - (a.updated || 0));
        root.conversations = list.slice(0, 60);
        root.queueHistoryWrite(root.historySaveSql(id, title, updated, kept));
    }

    // opencode assigns the session id on the first event of a run. Move the
    // open conversation under the real id so the list does not duplicate it.
    function adoptSessionId(id) {
        if (!id || id === root.sessionId) return;
        const previous = root.activeConvId;
        if (previous.length > 0 && previous !== id) {
            const key = root.sqlLiteral(id);
            const old = root.sqlLiteral(previous);
            root.queueHistoryWrite(root.historySchema
                + "\nUPDATE conversations SET id = " + key + " WHERE id = " + old + ";"
                + "\nUPDATE messages SET conversation_id = " + key
                + " WHERE conversation_id = " + old + ";");
            const list = root.conversations.slice();
            for (let i = 0; i < list.length; i += 1) {
                if (list[i].id === previous) {
                    list[i].id = id;
                    root.conversations = list;
                    break;
                }
            }
        }
        root.activeConvId = id;
        root.sessionId = id;
        root.saveState();
    }

    function updateMessage(idx, props) {
        if (idx < 0 || idx >= chat.count) return;
        for (const key in props) chat.setProperty(idx, key, props[key]);
    }

    function upsertText(partID, text) {
        let idx = partIndex[partID];
        if (idx === undefined) {
            idx = addMessage("assistant", text);
            partIndex[partID] = idx;
        } else {
            updateMessage(idx, { text: text });
        }
    }

    function upsertTool(part) {
        const state = part.state || {};
        const input = state.input || {};
        const detail = input.command || input.filePath || input.description || input.query || part.tool || "action";
        const out = state.output || state.error || "";
        const status = state.status || "running";
        const props = {
            command: String(detail),
            output: String(out),
            status: status,
            text: part.tool || "tool"
        };
        let idx = partIndex[part.id];
        if (idx === undefined) {
            idx = addMessage("tool", part.tool || "tool");
            partIndex[part.id] = idx;
        }
        updateMessage(idx, props);

        // Telemetry: one activity event per finished tool, with its duration.
        const partId = String(part.id || "");
        if (status === "running" || status === "pending") {
            if (root.toolStartTimes[partId] === undefined)
                root.toolStartTimes[partId] = Date.now();
        } else if (!root.toolFinished[partId]) {
            root.toolFinished[partId] = true;
            const started = root.toolStartTimes[partId] || 0;
            root.turnTools += 1;
            if (status !== "completed") root.turnToolFails += 1;
            root.emitEvent({
                event: "tool",
                ts: new Date().toISOString(),
                session: root.sessionId,
                tool: String(part.tool || "tool"),
                command: String(detail).slice(0, 500),
                status: String(status),
                ok: status === "completed",
                duration_ms: started ? Date.now() - started : 0
            });
        }

        // A finished tool stops the cast pose. A failed tool also makes the
        // pet sad: opencode still exits 0, so onExited never sees the error.
        toolActive = status === "running" || status === "pending";
        if (status === "completed") toolCount = toolCount + 1;
        else if (status === "error") pet.react("error");
    }

    function showError(err) {
        hasError = true;
        toolActive = false;
        let msg = "Unknown error";
        if (err) {
            if (typeof err === "string") msg = err;
            else msg = err.message || err.type || JSON.stringify(err);
        }
        // Quota errors come with a huge JSON blob inside
        const brace = msg.indexOf("{");
        if (msg.length > 220 && brace > 0) msg = msg.slice(0, brace).trim();
        root.turnError = msg;
        addMessage("system", "⚠ " + msg);
        pet.react("error");
    }

    function handleLine(line) {
        line = String(line).trim();
        if (line.length === 0 || line[0] !== "{") return;

        let ev;
        try { ev = JSON.parse(line); } catch (e) { return; }

        if (ev.sessionID && ev.sessionID !== root.sessionId) root.adoptSessionId(ev.sessionID);

        const part = ev.part || {};

        if (ev.type === "text" && part.text) upsertText(part.id, part.text);
        else if (ev.type === "tool_use" || ev.type === "tool") upsertTool(part);
        else if (ev.type === "error") showError(ev.error);
    }

    function send(text) {
        text = String(text || "").trim();
        if (text.length === 0) return;
        if (root.minimized) root.restorePet();
        if (root.authStatus === "missing") {
            addMessage("system", "OpenCode is not connected. Add your API key to continue.");
            root.chatOpen = true;
            root.openAuthDialog();
            return;
        }
        if (busy) {
            addMessage("system", "I'm still working on the previous request. Wait or press the stop button.");
            return;
        }

        addMessage("user", text);
        busy = true;
        toolActive = false;
        stopping = false;
        hasError = false;
        toolCount = 0;
        partIndex = ({});

        // per-turn telemetry
        root.turnPrompt = text;
        root.turnStarted = Date.now();
        root.turnTools = 0;
        root.turnToolFails = 0;
        root.turnError = "";
        root.turnLogged = false;
        root.toolStartTimes = ({});
        root.toolFinished = ({});

        root.saveHistory();

        const args = ["run", "--format", "json", "--model", modelName, "--agent", agentName];
        if (root.sessionId) args.push("--session", root.sessionId);
        args.push(text);

        pet.wake();

        // stdin closed: if opencode sees an open pipe it waits for EOF and hangs
        agent.command = ["sh", "-c", 'exec "$0" "$@" < /dev/null', opencodeBin].concat(args);
        agent.running = true;
    }

    function stopAgent() {
        if (agent.running) {
            stopping = true;
            agent.running = false;
        }
        busy = false;
        toolActive = false;
        addMessage("system", "Stopped.");
        root.logTurn(-1, "stopped");
        root.saveHistory();
    }

    function freshSession() {
        if (root.minimized) root.restorePet();
        if (busy) stopAgent();
        root.saveHistory();
        root.sessionId = "";
        root.activeConvId = "";
        root.saveState();
        chat.clear();
        partIndex = ({});
        toolCount = 0;
        toolActive = false;
        hasError = false;
        pet.wake();
        addMessage("assistant", "Done, starting from scratch. What do you need?");
    }

    function toggleChat() {
        if (root.minimized) {
            root.restorePet();
            chatOpen = true;
        } else {
            chatOpen = !chatOpen;
        }
        if (chatOpen) pet.wake();
        if (chatOpen && chat.count === 0) {
            addMessage("assistant", root.authMissing
                ? "Hi. I'm Frieren. Connect your OpenCode account with the banner below, then ask me anything."
                : "Hi. I'm Frieren. Ask me to do something on the system, or ask me anything.");
        }
    }

    // ---------------- activity hook (local dashboard feed) ----------------
    property var hookQueue: []

    Process {
        id: hookRunner
        property string payload: ""
        running: false
        stdinEnabled: true
        command: ["sh", root.hookPath]
        onStarted: {
            hookRunner.write(hookRunner.payload + "\n");
            hookRunner.payload = "";
            hookRunner.stdinEnabled = false;
        }
        onExited: {
            hookRunner.stdinEnabled = true;
            root.flushHooks();
        }
    }

    // Events are queued so a turn never blocks on the hook process.
    function emitEvent(event) {
        if (!root.logEnabled) return;
        root.hookQueue.push(JSON.stringify(event));
        root.flushHooks();
    }

    function flushHooks() {
        if (hookRunner.running || root.hookQueue.length === 0) return;
        hookRunner.payload = String(root.hookQueue.shift());
        hookRunner.running = true;
    }

    // One event per question, so a dashboard can chart outcomes per turn.
    // exit_code -1 means the run was stopped from the chat.
    function logTurn(exitCode, errorText) {
        if (root.turnLogged || root.turnStarted <= 0) return;
        root.turnLogged = true;
        root.emitEvent({
            event: "turn",
            ts: new Date().toISOString(),
            session: root.sessionId,
            prompt: root.turnPrompt.slice(0, 500),
            duration_ms: Date.now() - root.turnStarted,
            exit_code: exitCode,
            ok: exitCode === 0 && !root.hasError && root.turnToolFails === 0,
            tools_total: root.turnTools,
            tools_failed: root.turnToolFails,
            error: root.turnError.length > 0 ? root.turnError
                : (errorText || (exitCode !== 0 ? "exit " + exitCode : "")),
            model: root.modelName
        });
    }

    // ---------------- opencode account ----------------
    function parseAuthJson(raw) {
        const text = String(raw || "").trim();
        if (text.length === 0) return null;
        const start = text.indexOf("[");
        const end = text.lastIndexOf("]");
        if (start < 0 || end <= start) return null;
        try {
            return JSON.parse(text.slice(start, end + 1));
        } catch (e) {
            return null;
        }
    }

    function authEntry(list) {
        if (!Array.isArray(list)) return null;
        for (let i = 0; i < list.length; i += 1) {
            if (list[i] && list[i].id === root.authProvider) return list[i];
        }
        return null;
    }

    function authMethodList(entry) {
        if (!entry) return [];
        const connections = entry.connections || [];
        const methods = [];
        for (let i = 0; i < connections.length; i += 1) {
            const c = connections[i];
            const label = c.label || c.name || c.method;
            if (label) methods.push(String(label));
        }
        return methods;
    }

    function authCredentialList(entry) {
        if (!entry) return [];
        const connections = entry.connections || [];
        const credentials = [];
        for (let i = 0; i < connections.length; i += 1) {
            const c = connections[i];
            if (c.type !== "credential") continue;
            credentials.push({
                id: String(c.id || ""),
                label: String(c.label || ""),
                method: String(c.method || "")
            });
        }
        return credentials;
    }

    function applyAuthList(raw) {
        const list = root.parseAuthJson(raw);
        if (list === null) {
            root.authStatus = "error";
            root.authDetail = "No response from opencode.";
            root.authCredentials = [];
            return false;
        }
        const entry = root.authEntry(list);
        const connections = entry ? (entry.connections || []) : [];
        const methods = root.authMethodList(entry);
        const connected = connections.length > 0;
        root.authCredentials = root.authCredentialList(entry);
        const changed = root.authStatus !== (connected ? "connected" : "missing");
        root.authStatus = connected ? "connected" : "missing";
        root.authDetail = methods.join(", ");
        if (changed && root.stateLoaded) root.saveState();
        return true;
    }

    function cleanAuthOutput(out, err) {
        let text = String(err || "") + "\n" + String(out || "");
        text = text.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "");
        const lines = text.split("\n");
        const useful = [];
        for (let i = 0; i < lines.length; i += 1) {
            const line = lines[i].replace(/^[│┌└◇■\s]+/, "").trim();
            if (line.length > 0) useful.push(line);
        }
        if (useful.length === 0) return "opencode command failed.";
        return useful[useful.length - 1].slice(0, 240);
    }

    function randomHex(length) {
        let out = "";
        while (out.length < length) out += Math.floor(Math.random() * 16).toString(16);
        return out.slice(0, length);
    }

    function checkAuth() {
        if (authList.running || root.authSaving || root.authQueuedKey.length > 0) return;
        root.authChecking = true;
        authList.purpose = "status";
        authList.running = true;
    }

    function authRefresh() {
        if (authList.running || root.authSaving) return;
        authList.purpose = "refresh";
        authList.running = true;
    }

    function openAuthDialog() {
        root.authOpen = true;
        root.authMessage = "";
        root.authMessageOk = false;
        root.authMessageError = false;
        root.checkAuth();
    }

    function saveAuthKey(key) {
        if (root.authSaving || root.authQueuedKey.length > 0) return;
        key = String(key || "").trim();
        if (key.length === 0) {
            root.authMessage = "The API key is empty.";
            root.authMessageError = true;
            return;
        }
        if (authList.running) {
            root.authQueuedKey = key;
            return;
        }
        root.authMessage = "";
        root.authMessageOk = false;
        root.authMessageError = false;
        root.authSaving = true;
        root.authNewCredential = "cred_frieren_" + root.randomHex(16);
        const payload = [{
            id: root.authNewCredential,
            integrationID: root.authProvider,
            label: "Frieren",
            active: true,
            value: { type: "key", key: key }
        }];
        authImport.payload = JSON.stringify(payload);
        authImport.stdinEnabled = true;
        authImport.running = true;
    }

    function authImportDone(code, out, err) {
        if (code !== 0) {
            root.authFail(root.cleanAuthOutput(out, err));
            return;
        }
        authSwitch.command = [
            root.opencodeBin, "auth", "switch",
            root.authProvider, root.authNewCredential
        ];
        authSwitch.running = true;
    }

    function authSwitchDone(code, out, err) {
        if (code !== 0) {
            root.authRecoverNew(root.cleanAuthOutput(out, err));
            return;
        }
        authList.purpose = "verify";
        authList.running = true;
    }

    function authRecoverNew(message) {
        root.authFailMessage = message;
        authLogout.purpose = "recovery";
        authLogout.command = [
            root.opencodeBin, "auth", "logout",
            root.authProvider, root.authNewCredential
        ];
        authLogout.running = true;
    }

    function authCleanupStart(credentials) {
        const ids = [];
        for (let i = 0; i < credentials.length; i += 1) {
            const c = credentials[i];
            if (c.id === root.authNewCredential) continue;
            if (c.label === "Frieren" || c.id.indexOf("cred_frieren_") === 0) ids.push(c.id);
        }
        root.authCleanupIds = ids;
        root.authCleanupNext();
    }

    function authCleanupNext() {
        if (!root.authCleanupIds || root.authCleanupIds.length === 0) {
            authList.purpose = "final";
            authList.running = true;
            return;
        }
        const ids = root.authCleanupIds.slice();
        const id = ids.shift();
        root.authCleanupIds = ids;
        authLogout.purpose = "cleanup";
        authLogout.command = [
            root.opencodeBin, "auth", "logout",
            root.authProvider, id
        ];
        authLogout.running = true;
    }

    function authLogoutDone(code, out, err) {
        if (authLogout.purpose === "recovery") {
            root.authFail(root.authFailMessage);
            return;
        }
        root.authCleanupNext();
    }

    function authFail(message) {
        root.authSaving = false;
        root.authMessage = message;
        root.authMessageOk = false;
        root.authMessageError = true;
        Qt.callLater(root.authRefresh);
    }

    function authListDone(out, err, purpose, code) {
        if (purpose === "status") {
            root.authChecking = false;
            if (code !== 0) {
                root.authStatus = "error";
                root.authDetail = root.cleanAuthOutput(out, err);
                root.authCredentials = [];
            } else {
                root.applyAuthList(out);
            }
            if (root.authQueuedKey.length > 0) {
                const key = root.authQueuedKey;
                root.authQueuedKey = "";
                Qt.callLater(() => root.saveAuthKey(key));
            }
            return;
        }

        if (purpose === "verify") {
            const list = root.parseAuthJson(out);
            if (code !== 0 || list === null) {
                root.authFail(root.cleanAuthOutput(out, err));
                return;
            }
            const credentials = root.authCredentialList(root.authEntry(list));
            let found = false;
            for (let i = 0; i < credentials.length; i += 1) {
                if (credentials[i].id === root.authNewCredential) found = true;
            }
            if (!found) {
                root.authFail("opencode did not keep the new credential.");
                return;
            }
            root.authCleanupStart(credentials);
            return;
        }

        const applied = root.applyAuthList(out);
        root.authSaving = false;
        if (purpose === "final") {
            if (applied && root.authStatus === "connected") {
                root.authMessage = "Key saved.";
                root.authMessageOk = true;
                if (authDialog) authDialog.clearKey();
            } else {
                root.authMessage = "opencode did not keep the key.";
                root.authMessageError = true;
            }
        }
    }

    function startTerminalLogin() {
        if (terminalAuth.running) return;
        root.authMessage = "Finish the login in the terminal that just opened.";
        root.authMessageOk = false;
        root.authMessageError = false;
        terminalAuth.running = true;
    }

    Process {
        id: agent
        running: false
        stdinEnabled: false
        workingDirectory: root.home
        environment: ({
            PATH: root.home + "/.opencode/bin:/usr/local/bin:/usr/bin:/bin",
            NO_COLOR: "1"
        })

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root.handleLine(line)
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const s = String(line).trim();
                if (s.length > 0 && root.busy) console.log("[frieren]", s);
            }
        }

        onExited: (code, status) => {
            root.busy = false;
            root.toolActive = false;
            if (root.stopping) {
                root.stopping = false;
                return;
            }
            if (code === 0) {
                pet.react("ok");
            } else if (!root.hasError && code !== 130) {
                pet.react("error");
                root.addMessage("system", "opencode exited with code " + code + ".");
            }
            root.logTurn(code, "");
            root.saveHistory();
        }
    }

    // ---------------- opencode account (status, key, terminal login) ----------------
    Process {
        id: authList
        property string purpose: "status"
        running: false
        command: [root.opencodeBin, "auth", "list", "--format", "json"]
        stdout: StdioCollector { id: authListOut }
        stderr: StdioCollector { id: authListErr }
        onExited: (code, status) => root.authListDone(
            authListOut.text, authListErr.text, authList.purpose, code)
    }

    Process {
        id: authImport
        property string payload: ""
        running: false
        stdinEnabled: true
        command: [root.opencodeBin, "auth", "import"]
        stdout: StdioCollector { id: authImportOut }
        stderr: StdioCollector { id: authImportErr }
        onStarted: {
            authImport.write(authImport.payload + "\n");
            authImport.payload = "";
            authImport.stdinEnabled = false;
        }
        onExited: (code, status) => root.authImportDone(
            code, authImportOut.text, authImportErr.text)
    }

    Process {
        id: authSwitch
        running: false
        command: []
        stdout: StdioCollector { id: authSwitchOut }
        stderr: StdioCollector { id: authSwitchErr }
        onExited: (code, status) => root.authSwitchDone(
            code, authSwitchOut.text, authSwitchErr.text)
    }

    Process {
        id: authLogout
        property string purpose: "cleanup"
        running: false
        command: []
        stdout: StdioCollector { id: authLogoutOut }
        stderr: StdioCollector { id: authLogoutErr }
        onExited: (code, status) => root.authLogoutDone(
            code, authLogoutOut.text, authLogoutErr.text)
    }

    Process {
        id: terminalAuth
        running: false
        command: ["sh", "-c", root.terminalLauncher, root.opencodeBin, root.authProvider]
        stdout: SplitParser {
            onRead: line => console.log("[frieren-auth]", line)
        }
        stderr: SplitParser {
            onRead: line => console.log("[frieren-auth]", line)
        }
        onExited: (code, status) => {
            if (code === 127) {
                root.authMessage = "No terminal emulator found. Run: "
                    + root.opencodeBin + " auth login " + root.authProvider;
                root.authMessageError = true;
            } else {
                root.checkAuth();
            }
        }
    }

    Timer {
        interval: 4000
        repeat: true
        running: root.authOpen && !root.authSaving
        onTriggered: root.checkAuth()
    }

    Component.onCompleted: root.checkAuth()

    // ---------------- tray helper (StatusNotifierItem + DBusMenu) ----------------
    Process {
        id: trayHelper
        running: true
        stdinEnabled: false
        command: [
            root.home + "/.config/quickshell/frieren/frieren-tray",
            root.home + "/.config/quickshell/frieren/assets/frieren-icon.png",
            root.home + "/.config/quickshell/frieren/assets/frieren-icon-128.argb",
            root.home + "/.config/quickshell/frieren/assets/frieren-icon-64.argb",
            root.home + "/.config/quickshell/frieren/assets/frieren-icon-32.argb",
            root.statePath
        ]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => console.log("[frieren-tray]", line)
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => console.log("[frieren-tray]", line)
        }
        onExited: (code, status) => console.log("[frieren] tray helper exited with", code)
    }

    // ---------------- external control (keybinds, scripts) ----------------
    IpcHandler {
        target: "frieren"

        function toggle(): void { root.toggleChat() }

        function ask(text: string): void {
            root.chatOpen = true;
            root.send(text);
        }

        function fresh(): void { root.freshSession() }

        function stop(): void { root.stopAgent() }

        function hide(): void { root.chatOpen = false }

        function auth(): void { root.openAuthDialog() }

        function about(): void { root.aboutOpen = true }

        function ping(): string { return "pong" }

        function minimize(): void { root.minimizePet() }

        function restore(): void { root.restorePet() }

        function wander(mode: string): void {
            root.wanderEnabled = (mode === "toggle") ? !root.wanderEnabled : (mode === "true");
            root.saveState();
        }

        function sleep(mode: string): void {
            root.sleepEnabled = (mode === "toggle") ? !root.sleepEnabled : (mode === "true");
            if (!root.sleepEnabled && pet) pet.wake();
            root.saveState();
        }

        function blink(mode: string): void {
            root.blinkEnabled = (mode === "toggle") ? !root.blinkEnabled : (mode === "true");
            root.saveState();
        }

        function log(mode: string): void {
            root.logEnabled = (mode === "toggle") ? !root.logEnabled : (mode === "true");
            root.saveState();
        }

        function scale(value: string): void {
            const v = parseFloat(value);
            if (!isNaN(v)) {
                root.petScale = Math.max(0.7, Math.min(1.4, v));
                root.saveState();
            }
        }

        function resetpos(): void {
            root.petX = 80;
            root.petY = 220;
            root.petPlaced = false;
            root.placePet();
            if (root.petPlaced) root.saveState();
        }

        function quit(): void { Qt.quit() }
    }

    // ---------------- pet window (fullscreen with mask) ----------------
    PanelWindow {
        id: petWin

        visible: !root.minimized

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        color: "transparent"
        implicitWidth: petWin.screen ? petWin.screen.width : 1920
        implicitHeight: petWin.screen ? petWin.screen.height : 1080
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "frieren-pet"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region { item: hitArea }

        onWidthChanged: Qt.callLater(root.placePet)
        onHeightChanged: Qt.callLater(root.placePet)

        Rectangle {
            id: hitArea
            x: pet.x
            y: pet.y
            width: pet.width
            height: pet.height
            color: "transparent"
        }

        PetSprite {
            id: pet
            busy: root.busy
            toolActive: root.toolActive
            chatOpen: root.chatOpen
            lookDir: chatWin.onLeft ? -1 : 1
            wanderEnabled: root.wanderEnabled && !root.minimized
            sleepEnabled: root.sleepEnabled
            blinkEnabled: root.blinkEnabled
            uiScale: root.petScale
            accent: theme.accent
            danger: theme.danger
            textDim: theme.textDim
            surface: theme.surface
            outline: theme.outline
            onActivate: root.toggleChat()
            onMoved: {
                if (!root.isNearBar()) {
                    root.lastGoodX = pet.x;
                    root.lastGoodY = pet.y;
                }
                root.saveState();
                if (root.isNearBar()) root.minimizePet();
            }

            Component.onCompleted: Qt.callLater(root.placePet)
        }
    }

    // ---------------- chat bubble ----------------
    PanelWindow {
        id: chatWin

        visible: root.chatOpen && !root.minimized
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "frieren-chat"
        WlrLayershell.keyboardFocus: root.chatOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        focusable: true

        anchors {
            top: true
            left: true
        }

        implicitWidth: 430
        implicitHeight: Math.min(560, Math.max(320, petWin.height - 28))
        margins.top: chatTop()
        margins.left: chatLeft()

        readonly property bool onLeft: pet.x + pet.width + 14 + implicitWidth
            > (petWin.width > 0 ? petWin.width : 1920) - 14

        function chatLeft() {
            const w = implicitWidth;
            const gap = 14;
            const sw = petWin.width > 0 ? petWin.width : 1920;
            const x = onLeft ? pet.x - w - gap : pet.x + pet.width + gap;
            return Math.round(Math.max(gap, Math.min(x, sw - w - gap)));
        }

        function chatTop() {
            const h = implicitHeight;
            const gap = 14;
            const sh = petWin.height > 0 ? petWin.height : 1080;
            return Math.round(Math.max(gap, Math.min(pet.y + pet.height - h, sh - h - gap)));
        }

        ChatPanel {
            anchors.fill: parent
            theme: theme
            model: chat
            busy: root.busy
            hasSession: root.sessionId.length > 0
            authMissing: root.authMissing
            conversations: root.conversations

            onSubmit: text => root.send(text)
            onStop: root.stopAgent()
            onFresh: root.freshSession()
            onDismiss: root.chatOpen = false
            onConfigureAuth: root.openAuthDialog()
            onOpenConversation: id => root.openConversation(id)
            onDeleteConversation: id => root.deleteConversation(id)
        }
    }

    // ---------------- opencode account dialog ----------------
    PanelWindow {
        id: authWin

        visible: root.authOpen
        screen: petWin.screen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "frieren-auth"
        WlrLayershell.keyboardFocus: root.authOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        focusable: true

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        implicitWidth: authWin.screen ? authWin.screen.width : 1920
        implicitHeight: authWin.screen ? authWin.screen.height : 1080

        mask: Region { item: authDialog }

        onVisibleChanged: {
            if (visible) Qt.callLater(authDialog.focusKey);
        }

        AuthDialog {
            id: authDialog
            visible: authWin.visible
            anchors.centerIn: parent
            width: implicitWidth
            height: implicitHeight

            theme: theme
            provider: root.authProvider
            model: root.modelName
            status: root.authStatus
            detail: root.authDetail
            message: root.authMessage
            messageOk: root.authMessageOk
            messageError: root.authMessageError
            checking: root.authChecking
            busy: root.authSaving

            onSaveKey: key => root.saveAuthKey(key)
            onTerminalLogin: root.startTerminalLogin()
            onCheck: root.checkAuth()
            onClose: root.authOpen = false
        }
    }

    // ---------------- about dialog ----------------
    PanelWindow {
        id: aboutWin

        visible: root.aboutOpen
        screen: petWin.screen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "frieren-about"
        WlrLayershell.keyboardFocus: root.aboutOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        focusable: true

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        implicitWidth: aboutWin.screen ? aboutWin.screen.width : 1920
        implicitHeight: aboutWin.screen ? aboutWin.screen.height : 1080

        mask: Region { item: aboutDialog }

        AboutDialog {
            id: aboutDialog
            visible: aboutWin.visible
            anchors.centerIn: parent
            width: implicitWidth
            height: implicitHeight
            theme: theme
            onClose: root.aboutOpen = false
        }
    }
}
