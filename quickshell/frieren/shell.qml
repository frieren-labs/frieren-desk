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
    property int toolCount: 0
    property bool hasError: false

    // partID -> indice en el ListModel
    property var partIndex: ({})

    // ---------------- tema (matugen/DMS, con fallback) ----------------
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
            // dejamos el fallback
        }
    }

    function applyDmsType(raw) {
        try {
            const doc = JSON.parse(raw);
            if (doc.fontFamily) theme.fontFamily = doc.fontFamily;
            if (doc.monoFontFamily) theme.monoFamily = doc.monoFontFamily;
        } catch (e) {}
    }

    // ---------------- estado persistente (archivo propio) ----------------
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
        } catch (e) {}
        root.petPlaced = false;
        root.placePet();
    }

    property bool petPlaced: false

    function clampPet() {
        if (!pet || petWin.width < pet.width || petWin.height < pet.height) return;
        pet.x = Math.max(0, Math.min(pet.x, petWin.width - pet.width));
        pet.y = Math.max(0, Math.min(pet.y, petWin.height - pet.height));
    }

    // La superficie arranca en 500x500 y recien despues toma el tamano real:
    // no se puede clampear contra ese tamano provisorio.
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
            x: Math.round(pet ? pet.x : root.petX),
            y: Math.round(pet ? pet.y : root.petY),
            session: root.sessionId
        });
        stateWriter.command = [
            "sh", "-c",
            'mkdir -p "$0" && printf %s "$1" > "$0/state.json"',
            root.stateDir, payload
        ];
        stateWriter.running = true;
    }

    // ---------------- conversacion ----------------
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
        const detail = input.command || input.filePath || input.description || input.query || part.tool || "acción";
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
        if (status === "completed") toolCount = toolCount + 1;
    }

    function showError(err) {
        hasError = true;
        let msg = "Error desconocido";
        if (err) {
            if (typeof err === "string") msg = err;
            else msg = err.message || err.type || JSON.stringify(err);
        }
        // Los errores de cuota vienen con un JSON enorme adentro
        const brace = msg.indexOf("{");
        if (msg.length > 220 && brace > 0) msg = msg.slice(0, brace).trim();
        addMessage("system", "⚠ " + msg);
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
        if (busy) {
            addMessage("system", "Todavía estoy con lo anterior. Esperá o tocá el botón de detener.");
            return;
        }

        addMessage("user", text);
        busy = true;
        hasError = false;
        toolCount = 0;
        partIndex = ({});

        const args = ["run", "--format", "json", "--model", modelName, "--agent", agentName];
        if (root.sessionId) args.push("--session", root.sessionId);
        args.push(text);

        // stdin cerrado: si opencode ve un pipe abierto espera EOF y se cuelga
        agent.command = ["sh", "-c", 'exec "$0" "$@" < /dev/null', opencodeBin].concat(args);
        agent.running = true;
    }

    function stopAgent() {
        if (agent.running) agent.running = false;
        busy = false;
        addMessage("system", "Detenida.");
    }

    function freshSession() {
        if (busy) stopAgent();
        root.sessionId = "";
        root.saveState();
        chat.clear();
        partIndex = ({});
        toolCount = 0;
        hasError = false;
        addMessage("assistant", "Listo, empezamos de cero. ¿Qué necesitás?");
    }

    function toggleChat() {
        chatOpen = !chatOpen;
        if (chatOpen && chat.count === 0) {
            addMessage("assistant", "Hola. Soy Frieren. Pedime algo del sistema y lo hago, o preguntame lo que quieras.");
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
            if (code !== 0 && !root.hasError && code !== 130) {
                root.addMessage("system", "opencode terminó con código " + code + ".");
            }
        }
    }

    // ---------------- control externo (keybinds, scripts) ----------------
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
    }

    // ---------------- ventana de la mascota (pantalla completa con mascara) ----------------
    PanelWindow {
        id: petWin

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
            onActivate: root.toggleChat()
            onMoved: root.saveState()

            Component.onCompleted: Qt.callLater(root.placePet)
        }
    }

    // ---------------- burbuja de chat ----------------
    PanelWindow {
        id: chatWin

        visible: root.chatOpen
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

        function chatLeft() {
            const w = implicitWidth;
            const gap = 14;
            const sw = petWin.width > 0 ? petWin.width : 1920;
            let x = pet.x + pet.width + gap;
            if (x + w > sw - gap) x = pet.x - w - gap;
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
