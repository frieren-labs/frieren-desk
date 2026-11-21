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
    property real petScale: 1.0
    property real lastGoodX: 80
    property real lastGoodY: 220

    // partID -> index in the ListModel
    property var partIndex: ({})

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

    property real petX: 80
    property real petY: 220
    property string sessionId: ""

    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        onLoaded: root.loadState(text())
    }

    Process {
        id: stateWriter
        stdinEnabled: false
    }

    function loadState(raw) {
        try {
            const doc = JSON.parse(raw);
            if (typeof doc.x === "number") root.petX = doc.x;
            if (typeof doc.y === "number") root.petY = doc.y;
            if (typeof doc.session === "string") root.sessionId = doc.session;
            if (typeof doc.minimized === "boolean") root.minimized = doc.minimized;
            if (typeof doc.wander === "boolean") root.wanderEnabled = doc.wander;
            if (typeof doc.sleep === "boolean") root.sleepEnabled = doc.sleep;
            if (typeof doc.blink === "boolean") root.blinkEnabled = doc.blink;
            if (typeof doc.scale === "number")
                root.petScale = Math.max(0.7, Math.min(1.4, doc.scale));
        } catch (e) {}

        root.lastGoodX = root.petX;
        root.lastGoodY = root.petY;
        if (root.petY < 60) {
            root.lastGoodX = 80;
            root.lastGoodY = 220;
        }

        root.petPlaced = false;
        root.placePet();
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
            scale: root.petScale,
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
        root.petPlaced = false;
        Qt.callLater(root.placePet);
        root.saveState();
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
            status: ""
        });
        return chat.count - 1;
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
        addMessage("system", "⚠ " + msg);
        pet.react("error");
    }

    function handleLine(line) {
        line = String(line).trim();
        if (line.length === 0 || line[0] !== "{") return;

        let ev;
        try { ev = JSON.parse(line); } catch (e) { return; }

        if (ev.sessionID && ev.sessionID !== root.sessionId) {
            root.sessionId = ev.sessionID;
            root.saveState();
        }

        const part = ev.part || {};

        if (ev.type === "text" && part.text) upsertText(part.id, part.text);
        else if (ev.type === "tool_use" || ev.type === "tool") upsertTool(part);
        else if (ev.type === "error") showError(ev.error);
    }

    function send(text) {
        text = String(text || "").trim();
        if (text.length === 0) return;
        if (root.minimized) root.restorePet();
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
    }

    function freshSession() {
        if (root.minimized) root.restorePet();
        if (busy) stopAgent();
        root.sessionId = "";
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
            addMessage("assistant", "Hi. I'm Frieren. Ask me to do something on the system, or ask me anything.");
        }
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
        }
    }

    // ---------------- tray helper (StatusNotifierItem + DBusMenu) ----------------
    Process {
        id: trayHelper
        running: true
        stdinEnabled: false
        command: [
            "python3",
            root.home + "/.config/quickshell/frieren/tray.py",
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
            Qt.callLater(root.placePet);
            root.saveState();
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

            onSubmit: text => root.send(text)
            onStop: root.stopAgent()
            onFresh: root.freshSession()
            onDismiss: root.chatOpen = false
        }
    }
}
