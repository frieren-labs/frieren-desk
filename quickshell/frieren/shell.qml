import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "components"

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string opencodeBin: home + "/.opencode/bin/opencode"
    property string agentName: "frieren"
    property string modelName: "opencode-go/deepseek-v4.1-flash"
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
    property var availableModels: []
    property bool modelsLoading: false

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
    property bool soundEnabled: true
    property bool voiceSpeak: false
    property bool discordEnabled: false
    property string voiceId: "en-jenny"
    property int voiceVolume: 100
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
    property var searchResults: []
    property bool searching: false
    property string searchPending: ""
    property string searchExecuted: ""
    property var settingsDoc: ({})

    // per-turn telemetry (fed to the activity hook)
    property string turnPrompt: ""
    property real turnStarted: 0
    property int turnTools: 0
    property int turnToolFails: 0
    property string turnError: ""
    property bool turnLogged: false
    property var toolStartTimes: ({})
    property var toolFinished: ({})

    // liveliness + stats
    property int failStreak: 0
    property int okStreak: 0
    property var statsRows: []
    property bool statsReady: false
    property string pendingPrompt: ""

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
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/frieren"
    readonly property string settingsPath: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/frieren/settings.json"
    readonly property string statePath: stateDir + "/state.json"
    readonly property string dbPath: stateDir + "/frieren.db"
    readonly property string hookPath: home + "/.config/quickshell/frieren/hooks/frieren-log.sh"
    readonly property string soundsDir: home + "/.config/quickshell/frieren/assets/sounds"
    readonly property string toolsDir: home + "/.config/quickshell/frieren/tools"

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

    // User config: watched, applies live. Wins over state.json for model/agent.
    FileView {
        id: settingsFile
        path: root.settingsPath
        watchChanges: true
        printErrors: false
        onLoaded: root.parseSettings(text())
    }

    Process {
        id: settingsWriter
        property string payload: ""
        running: false
        stdinEnabled: true
        command: ["sh", "-c", 'mkdir -p "$(dirname "$0")" && cat > "$0"', root.settingsPath]
        onStarted: {
            settingsWriter.stdinEnabled = true;
            settingsWriter.write(settingsWriter.payload);
            settingsWriter.payload = "";
            settingsWriter.stdinEnabled = false;
        }
        onExited: {
            settingsWriter.stdinEnabled = true;
        }
    }

    // Keys present in settings.json win over state.json, whichever file
    // loads first (parseSettings caches the whole doc, loadState skips
    // keys it already provides, so both orders converge to settings).
    function hasSetting(key) {
        return root.settingsDoc
            && Object.prototype.hasOwnProperty.call(root.settingsDoc, key);
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
            if (typeof doc.model === "string" && doc.model.indexOf("/") > 0
                    && !root.hasSetting("model"))
                root.modelName = doc.model;
            if (typeof doc.minimized === "boolean") root.minimized = doc.minimized;
            if (typeof doc.wander === "boolean" && !root.hasSetting("wander"))
                root.wanderEnabled = doc.wander;
            if (typeof doc.sleep === "boolean" && !root.hasSetting("sleep"))
                root.sleepEnabled = doc.sleep;
            if (typeof doc.blink === "boolean" && !root.hasSetting("blink"))
                root.blinkEnabled = doc.blink;
            if (typeof doc.log === "boolean" && !root.hasSetting("log"))
                root.logEnabled = doc.log;
            if (typeof doc.sound === "boolean" && !root.hasSetting("sound"))
                root.soundEnabled = doc.sound;
            if (typeof doc.voice === "boolean" && !root.hasSetting("voice"))
                root.voiceSpeak = doc.voice;
            if (typeof doc.discord === "boolean" && !root.hasSetting("discord"))
                root.discordEnabled = doc.discord;
            if (typeof doc.voiceId === "string" && doc.voiceId.length > 0
                    && !root.hasSetting("voiceId"))
                root.voiceId = doc.voiceId;
            if (typeof doc.volume === "number" && !root.hasSetting("volume"))
                root.voiceVolume = Math.max(10, Math.min(150, Math.round(doc.volume)));
            if (typeof doc.scale === "number" && !root.hasSetting("scale"))
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
            model: root.modelName,
            minimized: root.minimized,
            wander: root.wanderEnabled,
            sleep: root.sleepEnabled,
            blink: root.blinkEnabled,
            log: root.logEnabled,
            sound: root.soundEnabled,
            voice: root.voiceSpeak,
            discord: root.discordEnabled,
            voiceId: root.voiceId,
            volume: root.voiceVolume,
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
        "CREATE INDEX IF NOT EXISTS conversations_updated ON conversations(updated_at);",
        "CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts",
        " USING fts5(conversation_id, role, text, tokenize='unicode61');",
        "CREATE TRIGGER IF NOT EXISTS messages_fts_insert AFTER INSERT ON messages BEGIN",
        "  INSERT INTO messages_fts(rowid, conversation_id, role, text)",
        "  VALUES (new.id, new.conversation_id, new.role, new.text);",
        "END;",
        "CREATE TRIGGER IF NOT EXISTS messages_fts_delete AFTER DELETE ON messages BEGIN",
        "  DELETE FROM messages_fts WHERE rowid = old.id;",
        "END;",
        "INSERT INTO messages_fts(rowid, conversation_id, role, text)",
        " SELECT id, conversation_id, role, text FROM messages",
        " WHERE id NOT IN (SELECT rowid FROM messages_fts);"
    ].join("\n")

    Process {
        id: historyLister
        running: false
        stdinEnabled: true
        command: ["sqlite3", "-json", "-cmd", ".timeout 5000", root.dbPath]
        stdout: StdioCollector { id: historyListOut }
        onStarted: {
            historyLister.stdinEnabled = true;
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
            historyLoader.stdinEnabled = true;
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
            historyWriter.stdinEnabled = true;
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

    Process {
        id: historySearcher
        property string query: ""
        running: false
        stdinEnabled: true
        command: ["sqlite3", "-json", "-cmd", ".timeout 5000", root.dbPath]
        stdout: StdioCollector { id: historySearchOut }
        onStarted: {
            if (historySearcher.query.length === 0)
                historySearcher.query = root.searchPending;
            historySearcher.stdinEnabled = true;
            historySearcher.write(root.historySearchSql(historySearcher.query));
            historySearcher.query = "";
            historySearcher.stdinEnabled = false;
        }
        onExited: (code, status) => root.applySearch(historySearchOut.text)
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

    // Deep search over titles (LIKE) and message bodies (FTS5).
    // Words are OR-ed: a conversation matches if any word hits.
    function ftsMatchExpr(q) {
        const words = String(q || "").split(/\s+/)
            .map(w => w.replace(/["'*():^+\-]/g, "").trim())
            .filter(w => w.length > 0)
            .slice(0, 6);
        if (words.length === 0) return "";
        return words.map(w => '"' + w + '"*').join(" OR ");
    }

    function historySearchSql(q) {
        const like = root.sqlLiteral("%" + String(q).replace(/[%_]/g, "") + "%");
        const match = root.ftsMatchExpr(q);
        let sql = "SELECT c.id, c.title, c.updated_at AS updated, "
            + "(SELECT count(*) FROM messages m WHERE m.conversation_id = c.id"
            + " AND m.role = 'user') AS questions "
            + "FROM conversations c WHERE c.title LIKE " + like;
        if (match.length > 0) {
            sql += " OR c.id IN (SELECT conversation_id FROM messages_fts"
                + " WHERE messages_fts MATCH " + root.sqlLiteral(match) + ")";
        }
        return root.historySchema + "\n" + sql + " ORDER BY c.updated_at DESC LIMIT 20;";
    }

    function searchHistory(q) {
        q = String(q || "").trim();
        root.searchPending = q;
        if (q.length < 2) {
            root.searchResults = [];
            root.searching = false;
            return;
        }
        root.searching = true;
        if (!historySearcher.running) {
            historySearcher.query = q;
            root.searchExecuted = q;
            historySearcher.running = true;
        }
    }

    function applySearch(raw) {
        let rows = [];
        try {
            rows = JSON.parse(String(raw || "[]"));
        } catch (e) {}
        if (!Array.isArray(rows)) rows = [];
        root.searchResults = rows.map(row => ({
            id: String(row.id || ""),
            title: String(row.title || ""),
            updated: Number(row.updated) || 0,
            questions: Number(row.questions) || 0
        })).filter(conv => conv.id.length > 0);
        // The query changed while sqlite was working: run again.
        if (root.searchPending.length >= 2 && root.searchPending !== root.searchExecuted) {
            historySearcher.query = root.searchPending;
            root.searchExecuted = root.searchPending;
            historySearcher.running = true;
        } else {
            root.searching = false;
        }
    }

    function showStats() {
        root.chatOpen = true;
        chatPanel.statsOpen = true;
        root.loadStats();
    }

    // External config: ~/.config/frieren/settings.json (watched, wins over state).
    function parseSettings(raw) {
        let doc = null;
        try {
            doc = JSON.parse(raw);
        } catch (e) {}
        if (!doc || typeof doc !== "object") return;
        root.settingsDoc = doc;
        if (typeof doc.model === "string" && doc.model.indexOf("/") > 0
                && doc.model !== root.modelName) {
            root.modelName = doc.model;
            root.saveState();
        }
        if (typeof doc.agent === "string" && doc.agent.length > 0
                && doc.agent !== root.agentName) {
            root.agentName = doc.agent;
        }
        let touched = false;
        if (typeof doc.wander === "boolean" && doc.wander !== root.wanderEnabled) {
            root.wanderEnabled = doc.wander;
            touched = true;
        }
        if (typeof doc.sleep === "boolean" && doc.sleep !== root.sleepEnabled) {
            root.sleepEnabled = doc.sleep;
            touched = true;
        }
        if (typeof doc.blink === "boolean" && doc.blink !== root.blinkEnabled) {
            root.blinkEnabled = doc.blink;
            touched = true;
        }
        if (typeof doc.log === "boolean" && doc.log !== root.logEnabled) {
            root.logEnabled = doc.log;
            touched = true;
        }
        if (typeof doc.sound === "boolean" && doc.sound !== root.soundEnabled) {
            root.soundEnabled = doc.sound;
            touched = true;
        }
        if (typeof doc.voice === "boolean" && doc.voice !== root.voiceSpeak) {
            root.voiceSpeak = doc.voice;
            touched = true;
        }
        if (typeof doc.discord === "boolean" && doc.discord !== root.discordEnabled) {
            root.discordEnabled = doc.discord;
            touched = true;
        }
        if (typeof doc.voiceId === "string" && doc.voiceId.length > 0
                && doc.voiceId !== root.voiceId) {
            root.voiceId = doc.voiceId;
            touched = true;
        }
        if (typeof doc.volume === "number") {
            const vol = Math.max(10, Math.min(150, Math.round(doc.volume)));
            if (vol !== root.voiceVolume) {
                root.voiceVolume = vol;
                touched = true;
            }
        }
        if (typeof doc.scale === "number") {
            const s = Math.max(0.7, Math.min(1.4, doc.scale));
            if (s !== root.petScale) {
                root.petScale = s;
                touched = true;
            }
        }
        if (touched) root.saveState();
    }

    function saveSettingsDoc() {
        settingsWriter.payload = JSON.stringify(root.settingsDoc, null, 2) + "\n";
        settingsWriter.running = true;
    }

    function mergeSettings(patch) {
        const doc = Object.assign({}, root.settingsDoc, patch);
        root.settingsDoc = doc;
        root.saveSettingsDoc();
    }

    // Toggle helpers shared by tray IPC, slash commands and settings import.
    // key: wander | sleep | blink | log | sound | voice | discord (settings key names).
    function setToggle(key, mode) {
        const v = (mode === "toggle")
            ? !root.toggleValue(key)
            : (mode === "true" || mode === "on" || mode === "1");
        if (key === "wander") root.wanderEnabled = v;
        else if (key === "sleep") root.sleepEnabled = v;
        else if (key === "blink") root.blinkEnabled = v;
        else if (key === "log") root.logEnabled = v;
        else if (key === "sound") root.soundEnabled = v;
        else if (key === "voice") root.voiceSpeak = v;
        else if (key === "discord") root.discordEnabled = v;
        else return;
        root.saveState();
        const patch = {};
        patch[key] = v;
        root.mergeSettings(patch);
    }

    function toggleValue(key) {
        if (key === "wander") return root.wanderEnabled;
        if (key === "sleep") return root.sleepEnabled;
        if (key === "blink") return root.blinkEnabled;
        if (key === "log") return root.logEnabled;
        if (key === "sound") return root.soundEnabled;
        if (key === "voice") return root.voiceSpeak;
        if (key === "discord") return root.discordEnabled;
        return false;
    }

    function setAgent(id) {
        id = String(id || "").trim();
        if (id.length === 0 || id === root.agentName) return;
        root.agentName = id;
        const doc = Object.assign({}, root.settingsDoc);
        doc.agent = id;
        root.settingsDoc = doc;
        root.saveSettingsDoc();
        root.addMessage("system", "Agent: " + id + ". Next message uses it.");
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

    // ---------------- export / stats / slash / hypr ----------------
    function conversationMarkdown() {
        const lines = [];
        lines.push("# Frieren conversation");
        lines.push("");
        for (let i = 0; i < chat.count; i += 1) {
            const m = chat.get(i);
            if (m.role === "user") lines.push("## You");
            else if (m.role === "assistant") lines.push("## Frieren");
            else if (m.role === "tool") lines.push("### `" + String(m.command || m.text || "action").slice(0, 120) + "`");
            else continue;
            if (m.text && m.role !== "tool") lines.push(String(m.text));
            if (m.output) {
                lines.push("");
                lines.push("```");
                lines.push(String(m.output).slice(0, 4000));
                lines.push("```");
            }
            lines.push("");
        }
        return lines.join("\n");
    }

    function exportConversation() {
        const md = root.conversationMarkdown();
        if (md.trim().length === 0) {
            root.addMessage("system", "Nothing to export yet.");
            return;
        }
        Quickshell.clipboardText = md;
        const id = root.activeConvId.length > 0 ? root.activeConvId : ("local-" + Date.now());
        exportWriter.target = root.stateDir + "/exports/conv-" + id + ".md";
        exportWriter.command = ["sh", "-c", 'mkdir -p "$(dirname "$0")" && cat > "$0"', exportWriter.target];
        exportWriter.payload = md;
        exportWriter.running = true;
        root.addMessage("system", "Conversation copied as Markdown and saved to exports/conv-" + id + ".md");
    }

    function loadStats() {
        if (statsLoader.running) return;
        root.statsReady = false;
        statsLoader.running = true;
    }

    function applyStats(raw) {
        let rows = [];
        try {
            rows = JSON.parse(String(raw || "[]"));
        } catch (e) {}
        if (!Array.isArray(rows)) rows = [];
        root.statsRows = rows;
        root.statsReady = true;
    }

    // Slash commands typed in the chat box. Returns true when handled.
    function handleSlash(text) {
        if (text[0] !== "/") return false;
        const parts = text.slice(1).split(/\s+/);
        const cmd = (parts[0] || "").toLowerCase();
        const arg = parts.slice(1).join(" ").trim();
        if (cmd === "new" || cmd === "fresh" || cmd === "clear") {
            root.freshSession();
            return true;
        }
        if (cmd === "export") {
            root.exportConversation();
            return true;
        }
        if (cmd === "stats") {
            root.showStats();
            return true;
        }
        if (cmd === "retry") {
            if (root.turnPrompt.length > 0 && !root.busy) root.send(root.turnPrompt);
            else root.addMessage("system", "Nothing to retry yet.");
            return true;
        }
        if (cmd === "help") {
            root.addMessage("system", "Commands: /new, /retry, /export, /stats, /model provider/name, /agent name, /sound on|off, /voice on|off|<id>, /volume 10-150, /discord on|off|test, /help. Prefix with @window to include the focused Hyprland window. Drop files into the chat to attach @paths.");
            return true;
        }
        if (cmd === "agent") {
            if (arg.length > 0) root.setAgent(arg);
            else root.addMessage("system", "Usage: /agent name (current " + root.agentName + ").");
            return true;
        }
        if (cmd === "sound") {
            root.setToggle("sound", arg.length > 0 ? arg : "toggle");
            root.addMessage("system", "Sound " + (root.soundEnabled ? "on." : "off."));
            return true;
        }
        if (cmd === "voice") {
            if (arg.length === 0) {
                root.addMessage("system", "Voice replies " + (root.voiceSpeak ? "on" : "off")
                    + " (" + root.voiceId + " at " + root.voiceVolume + "%). /voice on|off|<id>, voices: frieren-voice list.");
            } else if (arg === "on" || arg === "off" || arg === "toggle") {
                root.setToggle("voice", arg);
                root.addMessage("system", "Voice replies " + (root.voiceSpeak ? "on" : "off")
                    + " (" + root.voiceId + " at " + root.voiceVolume + "%).");
            } else {
                root.setVoice(arg);
            }
            return true;
        }
        if (cmd === "volume") {
            root.setVolume(arg);
            return true;
        }
        if (cmd === "discord") {
            if (arg === "test") {
                root.testDiscord();
            } else if (arg.length > 0) {
                root.setToggle("discord", arg);
                root.addMessage("system", "Discord alerts "
                    + (root.discordEnabled ? "on." : "off.")
                    + " Webhook lives in ~/.config/frieren/discord-webhook.env (mode 600).");
            } else {
                root.addMessage("system", "Discord alerts "
                    + (root.discordEnabled ? "on." : "off.")
                    + " /discord on|off|test.");
            }
            return true;
        }
        if (cmd === "model") {
            if (arg.length > 0) {
                if (arg.indexOf("/") > 0) root.setModel(arg);
                else root.addMessage("system", "Usage: /model provider/name (current " + root.modelName + ").");
            } else {
                root.addMessage("system", "Usage: /model provider/name (current " + root.modelName + ").");
            }
            return true;
        }
        return false;
    }

    function sendWithHypr(text) {
        // @window prefix (or hypr auto-context when available) adds the
        // focused Hyprland window to the prompt so "fix this" works.
        if (text.indexOf("@window") < 0) {
            root.startAgent(text);
            return;
        }
        root.pendingPrompt = text;
        hyprCtx.running = true;
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
        if (pet) {
            if (status === "running" || status === "pending") {
                const readers = ["read", "fetch", "webfetch", "glob", "grep",
                    "search", "Read", "Fetch", "Glob", "Grep"];
                pet.reading = readers.indexOf(String(part.tool || "")) >= 0;
            } else {
                pet.reading = false;
            }
        }
    }

    function showError(err) {
        hasError = true;
        toolActive = false;
        root.failStreak += 1;
        root.okStreak = 0;
        root.playSound("thud");
        let msg = "Unknown error";
        if (err) {
            if (typeof err === "string") msg = err;
            else msg = err.message || err.type || JSON.stringify(err);
        }
        // Quota errors come with a huge JSON blob inside
        const brace = msg.indexOf("{");
        if (msg.length > 220 && brace > 0) msg = msg.slice(0, brace).trim();
        if (root.failStreak >= 3) msg += " (" + root.failStreak + " in a row, want to try another way?)";
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

    function startAgent(text) {
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
        if (root.handleSlash(text)) return;
        root.playSound("pop");
        root.sendWithHypr(text);
    }

    function stopAgent() {
        if (agent.running) {
            stopping = true;
            agent.running = false;
        }
        busy = false;
        toolActive = false;
        if (pet) pet.reading = false;
        root.playSound("pop");
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
        root.okStreak = 0;
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
            hookRunner.stdinEnabled = true;
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

    Process {
        id: exportWriter
        property string payload: ""
        property string target: ""
        running: false
        stdinEnabled: true
        command: ["sh", "-c", 'mkdir -p "$(dirname "$0")" && cat > "$0"', target]
        onStarted: {
            exportWriter.stdinEnabled = true;
            exportWriter.write(exportWriter.payload);
            exportWriter.payload = "";
            exportWriter.stdinEnabled = false;
        }
        onExited: {
            exportWriter.stdinEnabled = true;
        }
    }

    Process {
        id: statsLoader
        running: false
        stdinEnabled: true
        command: ["sqlite3", "-json", "-cmd", ".timeout 5000", root.dbPath]
        stdout: StdioCollector { id: statsOut }
        onStarted: {
            statsLoader.stdinEnabled = true;
            statsLoader.write("SELECT * FROM daily ORDER BY day DESC LIMIT 14;");
            statsLoader.stdinEnabled = false;
        }
        onExited: (code, status) => root.applyStats(statsOut.text)
    }

    Process {
        id: hyprCtx
        running: false
        stdout: StdioCollector { id: hyprOut }
        stderr: StdioCollector { id: hyprErr }
        command: ["sh", "-c", 'command -v hyprctl >/dev/null 2>&1 || exit 0; hyprctl activewindow -j 2>/dev/null || echo "{}"']
        onExited: (code, status) => {
            let extra = "";
            try {
                const w = JSON.parse(String(hyprOut.text || "{}"));
                if (w && (w.title || w.class)) {
                    extra = "\n\n[Focused window: " + String(w.class || "") + " - " + String(w.title || "").slice(0, 200) + "]";
                }
            } catch (e) {}
            const base = root.pendingPrompt.replace("@window", "").trim();
            root.pendingPrompt = "";
            root.startAgent(extra ? base + extra : base);
        }
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

    // ---------------- sound, notify, voice, backup ----------------
    function playSound(name) {
        if (!root.soundEnabled) return;
        soundRunner.sound = name;
        if (!soundRunner.running) soundRunner.running = true;
    }

    Process {
        id: soundRunner
        property string sound: "pop"
        running: false
        command: ["sh", "-c",
            'f="$0"; [ -f "$f" ] || exit 0;'
            + ' paplay "$f" 2>/dev/null || aplay -q "$f" 2>/dev/null'
            + ' || ffplay -nodisp -autoexit -loglevel quiet "$f" 2>/dev/null || true',
            root.soundsDir + "/pop.wav"]
        onStarted: {
            soundRunner.command = ["sh", "-c",
                'f="$0"; [ -f "$f" ] || exit 0;'
                + ' paplay "$f" 2>/dev/null || aplay -q "$f" 2>/dev/null'
                + ' || ffplay -nodisp -autoexit -loglevel quiet "$f" 2>/dev/null || true',
                root.soundsDir + "/" + soundRunner.sound + ".wav"];
        }
    }

    // Local notify-send plus an optional Discord webhook embed, fanned out
    // by tools/frieren-notify.sh. The webhook URL never travels in argv:
    // the script reads it from the env file itself.
    function notifyTurn(title, body, event) {
        notifier.title = String(title || "Frieren").slice(0, 60);
        notifier.body = String(body || "").slice(0, 200);
        notifier.event = String(event || "info").slice(0, 20);
        if (!notifier.running) notifier.running = true;
    }

    function testDiscord() {
        if (discordTest.running) return;
        root.addMessage("system", "Discord: posting a test embed...");
        discordTest.running = true;
    }

    Process {
        id: notifier
        property string title: "Frieren"
        property string body: ""
        property string event: "info"
        running: false
        command: ["sh", root.toolsDir + "/frieren-notify.sh",
            "Frieren", "", "info"]
        onStarted: {
            notifier.command = ["sh", root.toolsDir + "/frieren-notify.sh",
                notifier.title, notifier.body, notifier.event];
        }
    }

    Process {
        id: discordTest
        running: false
        stdout: StdioCollector { id: discordTestOut }
        stderr: StdioCollector { id: discordTestErr }
        command: ["sh", root.toolsDir + "/frieren-notify.sh",
            "--test", "--event", "test"]
        onExited: (code, status) => {
            if (code === 0)
                root.addMessage("system", String(discordTestOut.text || "Discord: test posted.").trim().slice(0, 200));
            else
                root.addMessage("system", "Discord test failed: "
                    + String(discordTestErr.text || discordTestOut.text || ("exit " + code)).trim().slice(0, 200));
        }
    }

    function lastAssistantText() {
        for (let i = chat.count - 1; i >= 0; i -= 1) {
            const m = chat.get(i);
            if (m.role === "assistant" && String(m.text || "").trim().length > 0)
                return String(m.text);
        }
        return "";
    }

    function speak(text) {
        text = String(text || "").trim();
        if (text.length === 0) text = root.lastAssistantText();
        if (text.length === 0) {
            root.addMessage("system", "Nothing to read aloud yet.");
            return;
        }
        sayRunner.payload = text;
        sayRunner.command = ["sh", root.toolsDir + "/frieren-say.sh",
            root.voiceId, String(root.voiceVolume)];
        if (!sayRunner.running) sayRunner.running = true;
    }

    function setVoice(id) {
        id = String(id || "").trim();
        if (id.length === 0 || id === root.voiceId) return;
        root.voiceId = id;
        root.voiceSpeak = true;
        root.saveState();
        root.mergeSettings({ voiceId: id, voice: true });
        root.addMessage("system", "Voice: " + id + ". Next replies speak with it.");
    }

    function setVolume(value) {
        let v = parseInt(value, 10);
        if (isNaN(v)) {
            root.addMessage("system", "Usage: /volume 10-150 (current " + root.voiceVolume + ").");
            return;
        }
        v = Math.max(10, Math.min(150, v));
        if (v === root.voiceVolume) return;
        root.voiceVolume = v;
        root.saveState();
        root.mergeSettings({ volume: v });
        root.addMessage("system", "Voice volume: " + v + "%.");
    }

    Process {
        id: sayRunner
        property string payload: ""
        running: false
        stdinEnabled: true
        command: ["sh", root.toolsDir + "/frieren-say.sh"]
        stdout: StdioCollector { id: sayOut }
        stderr: StdioCollector { id: sayErr }
        onStarted: {
            sayRunner.stdinEnabled = true;
            sayRunner.write(sayRunner.payload);
            sayRunner.payload = "";
            sayRunner.stdinEnabled = false;
        }
        onExited: (code, status) => {
            sayRunner.stdinEnabled = true;
            if (code !== 0)
                root.addMessage("system", "Voice: " + String(sayErr.text || sayOut.text || "engine not available").trim().slice(0, 200));
        }
    }

    // Push-to-talk: first call records, second call stops and transcribes.
    function toggleDictation() {
        if (listenRecorder.running) {
            listenRecorder.running = false;
            return;
        }
        if (transcribeRunner.running) return;
        listenRecorder.running = true;
        root.addMessage("system", "Listening… call listen again (or the mic button) to stop.");
    }

    Process {
        id: listenRecorder
        running: false
        command: ["sh", root.toolsDir + "/frieren-listen.sh", "record",
            root.stateDir + "/dictate.wav"]
        stderr: StdioCollector { id: listenErr }
        onExited: (code, status) => {
            if (code !== 0 && String(listenErr.text || "").trim().length > 0)
                root.addMessage("system", "Mic: " + String(listenErr.text).trim().slice(0, 200));
            else if (!transcribeRunner.running) transcribeRunner.running = true;
        }
    }

    Process {
        id: transcribeRunner
        running: false
        command: ["sh", root.toolsDir + "/frieren-listen.sh", "transcribe",
            root.stateDir + "/dictate.wav"]
        stdout: StdioCollector { id: transcribeOut }
        stderr: StdioCollector { id: transcribeErr }
        onExited: (code, status) => {
            const text = String(transcribeOut.text || "").trim();
            if (code === 0 && text.length > 0) chatPanel.appendInput(text);
            else root.addMessage("system", "Dictation: "
                + String(transcribeErr.text || "no speech recognized").trim().slice(0, 200));
        }
    }

    function runBackup() {
        if (backupRunner.running) return;
        backupRunner.running = true;
    }

    Process {
        id: backupRunner
        running: false
        stdout: StdioCollector { id: backupOut }
        stderr: StdioCollector { id: backupErr }
        command: ["sh", "-c", 'exec "$0" backup',
            (Quickshell.env("XDG_BIN_HOME") || home + "/.local/bin") + "/frieren-backup"]
        onExited: (code, status) => {
            if (code === 0) {
                const msg = String(backupOut.text || "Backup done.").trim().slice(0, 200);
                root.addMessage("system", msg);
                root.notifyTurn("Frieren backup", msg, "backup");
            } else {
                const msg = "Backup: " + String(backupErr.text || "failed").trim().slice(0, 200);
                root.addMessage("system", msg);
                root.notifyTurn("Frieren backup", msg, "error");
            }
        }
    }

    function openHistory() {
        if (root.minimized) root.restorePet();
        root.chatOpen = true;
        chatPanel.historyOpen = true;
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
        root.refreshModels();
    }

    function refreshModels() {
        if (modelLister.running) return;
        root.modelsLoading = true;
        modelLister.running = true;
    }

    function applyModelList(raw) {
        root.modelsLoading = false;
        const lines = String(raw || "").split("\n");
        const out = [];
        for (let i = 0; i < lines.length; i += 1) {
            const m = lines[i].trim();
            if (m.length > 0 && m.indexOf("/") > 0 && out.indexOf(m) < 0) out.push(m);
        }
        // Current provider first so the relevant models are on top.
        const prov = root.authProvider;
        out.sort((a, b) => {
            const ap = a.indexOf(prov + "/") === 0 ? 0 : 1;
            const bp = b.indexOf(prov + "/") === 0 ? 0 : 1;
            if (ap !== bp) return ap - bp;
            return a < b ? -1 : (a > b ? 1 : 0);
        });
        root.availableModels = out;
    }

    function setModel(id) {
        id = String(id || "").trim();
        if (id.length === 0 || id.indexOf("/") < 0) return;
        if (id === root.modelName) return;
        root.modelName = id;
        root.saveState();
        const doc = Object.assign({}, root.settingsDoc);
        doc.model = id;
        root.settingsDoc = doc;
        root.saveSettingsDoc();
        root.authMessage = "Model: " + id + ". Next message uses it.";
        root.authMessageOk = true;
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
            if (pet) pet.reading = false;
            if (root.stopping) {
                root.stopping = false;
                return;
            }
            const clean = code === 0 && !root.hasError && root.turnToolFails === 0;
            const duration = root.turnStarted > 0 ? Date.now() - root.turnStarted : 0;
            if (clean) {
                root.failStreak = 0;
                root.okStreak += 1;
                root.playSound("chime");
                pet.react("ok");
                if (root.voiceSpeak) root.speak("");
            } else {
                if (code !== 130) {
                    root.failStreak += 1;
                    root.playSound("thud");
                }
                root.okStreak = 0;
                if (!root.hasError) pet.react("error");
                if (!root.hasError && code !== 0 && code !== 130)
                    root.addMessage("system", "opencode exited with code " + code + ".");
            }
            // Nudge when a long turn finishes while the chat is closed.
            if (!root.chatOpen && duration >= 30000) {
                if (clean) root.notifyTurn("Frieren: done", "Finished in " + Math.round(duration / 1000) + "s.", "done");
                else if (code !== 130) root.notifyTurn("Frieren: error", String(root.turnError || ("exit " + code)).slice(0, 160), "error");
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
            authImport.stdinEnabled = true;
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
        id: modelLister
        running: false
        command: [root.opencodeBin, "models"]
        stdout: StdioCollector { id: modelListOut }
        stderr: StdioCollector { id: modelListErr }
        onExited: (code, status) => root.applyModelList(modelListOut.text)
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
            root.statePath,
            (Quickshell.env("XDG_DATA_HOME") || root.home + "/.local/share") + "/frieren/voice/voices"
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

        function exportmd(): void { root.exportConversation() }

        function stats(): void {
            root.showStats();
        }

        function hide(): void { root.chatOpen = false }

        function auth(): void { root.openAuthDialog() }

        function about(): void { root.aboutOpen = true }

        function ping(): string { return "pong" }

        function minimize(): void { root.minimizePet() }

        function restore(): void { root.restorePet() }

        function wander(mode: string): void { root.setToggle("wander", mode) }

        function sleep(mode: string): void {
            root.setToggle("sleep", mode);
            if (!root.sleepEnabled && pet) pet.wake();
        }

        function blink(mode: string): void { root.setToggle("blink", mode) }

        function log(mode: string): void { root.setToggle("log", mode) }

        function sound(mode: string): void { root.setToggle("sound", mode) }

        function voice(mode: string): void { root.setToggle("voice", mode) }

        function discord(mode: string): void {
            if (mode === "test") root.testDiscord();
            else root.setToggle("discord", mode);
        }

        function voiceid(id: string): void { root.setVoice(id) }

        function volume(value: string): void { root.setVolume(value) }

        function backup(): void { root.runBackup() }

        function listen(): void { root.toggleDictation() }

        function say(text: string): void { root.speak(text) }

        function scale(value: string): void {
            const v = parseFloat(value);
            if (!isNaN(v)) {
                root.petScale = Math.max(0.7, Math.min(1.4, v));
                root.saveState();
                root.mergeSettings({ scale: root.petScale });
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
            streak: root.okStreak
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
            onHistoryRequest: root.openHistory()
            onDoubleActivate: {
                root.chatOpen = true;
                root.freshSession();
            }
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
            id: chatPanel
            anchors.fill: parent
            theme: theme
            model: chat
            busy: root.busy
            hasSession: root.sessionId.length > 0
            authMissing: root.authMissing
            conversations: root.conversations
            searchResults: root.searchResults
            searching: root.searching
            statsRows: root.statsRows
            statsLoading: statsLoader.running
            dictating: listenRecorder.running

            onSubmit: text => root.send(text)
            onStop: root.stopAgent()
            onFresh: root.freshSession()
            onDismiss: root.chatOpen = false
            onConfigureAuth: root.openAuthDialog()
            onOpenConversation: id => root.openConversation(id)
            onDeleteConversation: id => root.deleteConversation(id)
            onExportRequested: root.exportConversation()
            onStatsRequested: root.loadStats()
            onSearchHistory: q => root.searchHistory(q)
            onDictate: root.toggleDictation()
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
            models: root.availableModels
            modelsLoading: root.modelsLoading
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
            onSaveModel: id => root.setModel(id)
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
