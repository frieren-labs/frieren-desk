import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property real uiScale: 1.0

    width: 168 * uiScale
    height: 188 * uiScale

    // ---------------- inputs from shell.qml ----------------
    property bool busy: false          // opencode is thinking
    property bool toolActive: false    // a tool is running (casting)
    property bool chatOpen: false
    property int lookDir: 1            // +1 chat on the right, -1 on the left
    property bool wanderEnabled: true
    property bool sleepEnabled: true
    property bool blinkEnabled: true

    // ---------------- theme (matugen/DMS) ----------------
    property color accent: "#d0bcff"
    property color danger: "#f2b8b5"
    property color textDim: "#cac4cf"
    property color surface: "#211f24"
    property color outline: "#49454e"

    // ---------------- internal state ----------------
    property bool asleep: false
    property bool wandering: false
    property string reaction: ""       // "", "ok", "error", "wake"
    property bool reading: false
    property int streak: 0
    property int idleSeconds: 0
    property real dragLean: 0
    property real wanderLean: 0
    property real shakeX: 0
    property real castPhase: 0
    property real sleepPhase: 0
    property real burst: 0
    property real blinkOpacity: 0

    property bool hovered: mouse.containsMouse || mouse.drag.active

    signal activate()
    signal historyRequest()
    signal doubleActivate()
    signal moved(real x, real y)

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string assets: home + "/.config/quickshell/frieren/assets/"
    readonly property string baseSprite: assets + "poses/idle.png"

    // Poses are authored on this 228x256 canvas.
    readonly property int spriteW: 228
    readonly property int spriteH: 256

    // ---------------- poses ----------------
    property var poses: ({})
    property var hints: ({})
    property bool walkTick: false
    property int hintTick: 0

    FileView {
        path: root.assets + "poses/poses.json"
        printErrors: false
        onLoaded: {
            try {
                const doc = JSON.parse(text());
                root.poses = doc.poses || ({});
                root.hints = doc.hints || ({});
            } catch (e) {
                root.poses = ({});
                root.hints = ({});
            }
        }
    }

    readonly property string mood: {
        if (reaction === "error") return "sad";
        if (reaction === "wake") return "greet";
        if (reaction === "ok")
            return streak >= 3 ? "celebrate" : "happy";
        if (asleep) return "sleep";
        if (reading) return "reading";
        if (toolActive) return "cast";
        if (busy) return "talk";
        if (chatOpen) return "listen";
        if (wandering) return "walk";
        if (idleSeconds >= 60) return "think"; // daydreaming before sleep
        return "idle";
    }

    // Walk alternates two frames; every other mood is a single pose file.
    readonly property string poseKey: {
        if (root.mood !== "walk") return root.mood;
        if (root.walkTick) return "walk-2";
        return "walk-1";
    }

    readonly property var poseMeta: root.poses[root.poseKey] || root.poses["idle"] || null
    readonly property string poseUrl: {
        const meta = root.poseMeta;
        if (meta && meta.file) return root.assets + "poses/" + meta.file;
        return root.baseSprite;
    }

    readonly property var eyeRects: (root.poseMeta && root.poseMeta.eyes) ? root.poseMeta.eyes : []
    readonly property color skinColor: (root.poseMeta && root.poseMeta.skin) ? root.poseMeta.skin : "#fae7d7"
    readonly property var glowPoint: (root.poseMeta && root.poseMeta.glow) ? root.poseMeta.glow : [59, 116]

    // ---------------- canvas geometry ----------------
    readonly property real fitW: Math.min(width, height * spriteW / spriteH)
    readonly property real fitH: fitW * spriteH / spriteW
    readonly property real fitX: (width - fitW) / 2
    readonly property real fitY: (height - fitH) / 2

    function sx(v) { return fitX + v * fitW / spriteW }
    function sy(v) { return fitY + v * fitH / spriteH }
    function spanX(v) { return v * fitW / spriteW }
    function spanY(v) { return v * fitH / spriteH }

    // ---------------- lean ----------------
    readonly property real hoverLean: {
        if (!mouse.containsMouse || mouse.drag.active) return 0;
        return Math.max(-6, Math.min(6, ((mouse.mouseX / width) - 0.5) * 10));
    }
    readonly property real chatLean: root.chatOpen ? 2.5 * root.lookDir : 0
    readonly property real leanAngle: hoverLean + dragLean + wanderLean + chatLean
    Behavior on wanderLean { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on dragLean { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // ---------------- status label ----------------
    function timeGreeting() {
        const h = new Date().getHours();
        if (h < 6) return "still up?";
        if (h < 12) return "good morning";
        if (h < 20) return "good afternoon";
        return "good evening";
    }

    // Hint lines live in poses.json (data-driven, like the poses);
    // QML only keeps the dynamic specials.
    readonly property var hintLines: {
        const lines = root.hints[root.mood];
        return Array.isArray(lines) ? lines : [];
    }

    readonly property string hintText: {
        if (root.asleep) return "";
        if (root.reaction === "error") return "oops…";
        if (root.reaction === "ok" || root.reaction === "wake")
            return root.streak >= 3 ? "amazing!" : "done";
        if (root.hovered && !root.chatOpen) return root.timeGreeting();
        if (root.hintLines.length > 0)
            return root.hintLines[root.hintTick % root.hintLines.length];
        if (root.reading) return "reading…";
        if (root.toolActive) return "casting a spell…";
        if (root.busy) return "thinking…";
        return "ask me something";
    }
    readonly property bool hintVisible: hintText.length > 0
        && (hovered || busy || toolActive || reaction !== "")
    readonly property bool hintBelow: root.y < 34

    // ---------------- actions ----------------
    onSleepEnabledChanged: {
        if (!root.sleepEnabled && root.asleep) root.asleep = false;
    }

    function resetIdle() { root.idleSeconds = 0 }

    function wake() {
        root.resetIdle();
        if (root.asleep) {
            root.asleep = false;
            root.react("wake");
        }
    }

    function react(kind) {
        root.reaction = kind;
        reactionTimer.restart();
        if (kind === "ok" || kind === "wake") jumpAnim.restart();
        if (kind === "ok") burstAnim.restart();
        if (kind === "error") shakeAnim.restart();
        root.resetIdle();
    }

    function wander() {
        if (!parent || !root.wanderEnabled) return;
        const maxX = Math.max(0, parent.width - root.width);
        const maxY = Math.max(0, parent.height - root.height);
        if (maxX <= 0 || maxY <= 0) return;

        // Keep away from the top bar and the bottom dock, otherwise a wander
        // would look like a drop on the bar and minimize the pet.
        const top = Math.min(60, Math.max(6, maxY / 2));
        const bottom = Math.min(60, Math.max(6, maxY / 2));
        const tx = Math.max(6, Math.min(maxX - 6, root.x + (Math.random() * 2 - 1) * 130));
        const ty = Math.max(top, Math.min(maxY - bottom, root.y + (Math.random() * 2 - 1) * 70));
        const dx = tx - root.x;
        const dy = ty - root.y;
        if (Math.abs(dx) < 14 && Math.abs(dy) < 14) return;

        root.wandering = true;
        root.wanderLean = Math.max(-8, Math.min(8, dx * 0.06));
        wanderAnim.fromX = root.x;
        wanderAnim.toX = tx;
        wanderAnim.fromY = root.y;
        wanderAnim.toY = ty;
        wanderAnim.moveDuration = Math.max(800, Math.min(3200, Math.sqrt(dx * dx + dy * dy) * 22));
        wanderAnim.restart();
    }

    // ---------------- timers ----------------
    Timer {
        id: ticker
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            if (root.busy || root.toolActive || root.wandering || root.chatOpen
                    || root.hovered || root.asleep) {
                root.idleSeconds = 0;
                root.hintTick += 1;
                return;
            }
            root.idleSeconds += 1;
            if (root.idleSeconds >= 180 && root.sleepEnabled) root.asleep = true;
        }
    }

    Timer {
        id: blinkTimer
        interval: 4200
        repeat: true
        running: !root.asleep && root.blinkEnabled
        onTriggered: {
            interval = 2600 + Math.random() * 3800;
            if (!root.asleep && root.blinkEnabled && root.eyeRects.length > 0 && root.reaction === "")
                blinkAnim.restart();
        }
    }

    Timer {
        id: walkTimer
        interval: 380
        repeat: true
        running: root.wandering
        onTriggered: root.walkTick = !root.walkTick
    }

    Timer {
        id: wanderTimer
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            interval = 25000 + Math.random() * 35000;
            if (!root.wanderEnabled || root.chatOpen || root.busy || root.toolActive
                    || root.asleep || root.hovered || mouse.drag.active || root.wandering) return;
            root.wander();
        }
    }

    Timer {
        id: reactionTimer
        interval: 1100
        onTriggered: root.reaction = ""
    }

    // ---------------- animations ----------------
    SequentialAnimation {
        id: jumpAnim
        NumberAnimation {
            target: hop; property: "y"
            to: -16; duration: 170; easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: hop; property: "y"
            to: 0; duration: 320; easing.type: Easing.OutBounce
        }
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to: -5; duration: 50 }
        NumberAnimation { target: root; property: "shakeX"; to: 4; duration: 60 }
        NumberAnimation { target: root; property: "shakeX"; to: -3; duration: 60 }
        NumberAnimation { target: root; property: "shakeX"; to: 2; duration: 60 }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 80 }
    }

    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: root; property: "blinkOpacity"; from: 0; to: 1; duration: 55 }
        PauseAnimation { duration: 45 }
        NumberAnimation { target: root; property: "blinkOpacity"; from: 1; to: 0; duration: 85 }
    }

    SequentialAnimation {
        id: burstAnim
        NumberAnimation {
            target: root; property: "burst"
            from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic
        }
    }

    NumberAnimation {
        target: root; property: "castPhase"
        from: 0; to: 1; duration: 1200; loops: Animation.Infinite
        running: root.mood === "cast"
    }

    NumberAnimation {
        target: root; property: "sleepPhase"
        from: 0; to: 1; duration: 3200; loops: Animation.Infinite
        running: root.asleep
    }

    ParallelAnimation {
        id: wanderAnim
        property real fromX: 0
        property real toX: 0
        property real fromY: 0
        property real toY: 0
        property real moveDuration: 1000

        NumberAnimation {
            target: root; property: "x"
            from: wanderAnim.fromX; to: wanderAnim.toX
            duration: wanderAnim.moveDuration; easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root; property: "y"
            from: wanderAnim.fromY; to: wanderAnim.toY
            duration: wanderAnim.moveDuration; easing.type: Easing.InOutSine
        }
        onFinished: {
            root.wandering = false;
            root.wanderLean = 0;
            root.moved(root.x, root.y);
            root.resetIdle();
        }
    }

    // ---------------- ground shadow ----------------
    Rectangle {
        id: groundShadow
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - 13
        width: root.width * 0.52
        height: 9
        radius: height / 2
        color: "#000000"
        opacity: 0.26 * (root.asleep ? 0.6 : 1) * (1 - Math.min(0.7, Math.max(0, -hop.y) / 26))
        scale: 1 - Math.min(0.3, Math.max(0, -hop.y) / 60)
    }

    // ---------------- body ----------------
    Item {
        id: body
        anchors.fill: parent
        scale: root.hovered ? 1.05 : 1.0
        opacity: root.asleep ? 0.82 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 500 } }

        Item {
            id: hop
            x: root.shakeX
            y: 0
            width: root.width
            height: root.height

            Item {
                id: bobbing
                x: 0
                y: 0
                width: root.width
                height: root.height
                rotation: 0

                transform: [
                    Scale {
                        id: breatheScale
                        yScale: 1.0
                        origin.x: root.width / 2
                        origin.y: root.height
                    },
                    Shear {
                        id: hairShear
                        xAngle: 0
                        origin.x: root.width / 2
                        origin.y: root.height
                    },
                    Rotation {
                        id: leanRotation
                        angle: root.leanAngle
                        origin.x: root.width / 2
                        origin.y: root.height / 2
                    }
                ]

                // bobbing
                SequentialAnimation on y {
                    running: true
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 0
                        to: root.asleep ? -2 : (root.wandering ? -6 : -5)
                        duration: root.busy ? 900 : (root.wandering ? 300 : (root.asleep ? 3800 : 2300))
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: root.asleep ? -2 : (root.wandering ? -6 : -5)
                        to: 0
                        duration: root.busy ? 900 : (root.wandering ? 300 : (root.asleep ? 3800 : 2300))
                        easing.type: Easing.InOutSine
                    }
                }

                // sway
                SequentialAnimation on rotation {
                    running: true
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: -1.0; to: 1.0
                        duration: root.busy ? 2600 : (root.asleep ? 6000 : 3600)
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: 1.0; to: -1.0
                        duration: root.busy ? 2600 : (root.asleep ? 6000 : 3600)
                        easing.type: Easing.InOutSine
                    }
                }

                // breathing
                SequentialAnimation {
                    running: true
                    loops: Animation.Infinite
                    NumberAnimation {
                        target: breatheScale; property: "yScale"
                        from: 1.0; to: 1.012
                        duration: root.asleep ? 3800 : 2400
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        target: breatheScale; property: "yScale"
                        from: 1.012; to: 1.0
                        duration: root.asleep ? 3800 : 2400
                        easing.type: Easing.InOutSine
                    }
                }

                // hair sways slightly
                SequentialAnimation {
                    running: !root.asleep
                    loops: Animation.Infinite
                    NumberAnimation {
                        target: hairShear; property: "xAngle"
                        from: -0.6; to: 0.6; duration: 4800
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        target: hairShear; property: "xAngle"
                        from: 0.6; to: -0.6; duration: 4800
                        easing.type: Easing.InOutSine
                    }
                }

                // work halo
                Rectangle {
                    anchors.centerIn: parent
                    width: root.width * 0.92
                    height: width
                    radius: width / 2
                    color: root.accent
                    opacity: (root.busy || root.toolActive) && !root.asleep ? 0.12 : 0.0
                    z: -1
                    Behavior on opacity { NumberAnimation { duration: 400 } }
                }

                // sprite with cross-fade between poses
                Item {
                    id: spriteStack
                    width: root.width
                    height: root.height

                    property string wantedSource: root.poseUrl
                    property string currentSource: ""
                    property bool frontIsA: true

                    onWantedSourceChanged: if (wantedSource) show(wantedSource)
                    Component.onCompleted: {
                        if (wantedSource) {
                            spriteA.source = wantedSource;
                            currentSource = wantedSource;
                        }
                    }

                    Image {
                        id: spriteA
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        smooth: false
                        asynchronous: true
                        cache: true
                        opacity: 1
                    }

                    Image {
                        id: spriteB
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        smooth: false
                        asynchronous: true
                        cache: true
                        opacity: 0
                    }

                    NumberAnimation {
                        id: fadeIn
                        property: "opacity"
                        from: 0; to: 1; duration: 170
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        id: fadeOut
                        property: "opacity"
                        to: 0; duration: 170
                        easing.type: Easing.OutCubic
                    }

                    function show(src) {
                        if (!src || src === currentSource) return;
                        const incoming = frontIsA ? spriteB : spriteA;
                        const outgoing = frontIsA ? spriteA : spriteB;
                        incoming.source = src;
                        incoming.opacity = 0;
                        fadeIn.target = incoming;
                        fadeOut.target = outgoing;
                        fadeIn.restart();
                        fadeOut.restart();
                        frontIsA = !frontIsA;
                        currentSource = src;
                    }
                }

                // blink: cover each eye with the pose's skin color
                Item {
                    id: blinkLayer
                    visible: root.blinkOpacity > 0.01 && root.eyeRects.length > 0
                    opacity: root.blinkOpacity

                    Repeater {
                        model: root.eyeRects
                        Rectangle {
                            x: root.sx(modelData[0])
                            y: root.sy(modelData[1])
                            width: root.spanX(modelData[2])
                            height: root.spanY(modelData[3])
                            radius: height / 2
                            color: root.skinColor
                        }
                    }
                }

                // casting: glow and particles on the staff gem
                Item {
                    id: castLayer
                    visible: root.mood === "cast"

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: root.accent
                        x: root.sx(root.glowPoint[0]) - width / 2
                        y: root.sy(root.glowPoint[1]) - height / 2
                        opacity: 0.08 + 0.06 * (0.5 + 0.5 * Math.sin(root.castPhase * Math.PI * 2))
                    }

                    Repeater {
                        model: 6
                        Rectangle {
                            width: 3 + (index % 3)
                            height: width
                            radius: width / 2
                            color: index % 2 === 0 ? root.accent : "#fff2a8"

                            property real t: (root.castPhase + index * 0.17) % 1

                            x: root.sx(root.glowPoint[0])
                                + Math.sin((t + index) * Math.PI * 2) * 8
                                - width / 2
                            y: root.sy(root.glowPoint[1]) - t * 34 - height / 2
                            opacity: (1 - t) * 0.9
                        }
                    }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        color: root.accent
                        x: root.sx(root.glowPoint[0]) - width / 2
                        y: root.sy(root.glowPoint[1]) - height / 2
                        opacity: 0.22 + 0.18 * (0.5 + 0.5 * Math.sin(root.castPhase * Math.PI * 2))
                        scale: 0.85 + 0.2 * (0.5 + 0.5 * Math.sin(root.castPhase * Math.PI * 2))
                    }
                }

                // sparkles on success
                Item {
                    id: sparkleLayer
                    visible: root.burst > 0.001 && root.burst < 0.999

                    Repeater {
                        model: 6
                        Rectangle {
                            width: 5
                            height: 5
                            color: root.accent
                            rotation: 45

                            property real ang: index / 6 * Math.PI * 2
                            property real dist: root.burst * (18 + (index % 3) * 7)

                            x: root.width / 2 + Math.cos(ang) * dist - width / 2
                            y: root.height * 0.42 + Math.sin(ang) * dist - height / 2 - root.burst * 12
                            opacity: 1 - root.burst
                            scale: 0.5 + root.burst * 0.9
                        }
                    }
                }

                // sleeping: z z z
                Item {
                    id: sleepLayer
                    visible: root.asleep

                    Repeater {
                        model: 3
                        Text {
                            text: "z"
                            font.family: "Google Sans Flex"
                            font.pixelSize: 10 + index * 4
                            font.bold: index > 0
                            color: root.textDim

                            property real t: (root.sleepPhase + index * 0.28) % 1

                            x: root.width * 0.70 + t * 10 + index * 2
                            y: root.height * 0.14 - t * 24
                            opacity: (1 - t) * 0.85
                        }
                    }
                }

                // thinking: three dots
                Item {
                    id: thinkDots
                    visible: root.mood === "think"
                    x: root.width * 0.72
                    y: root.height * 0.13

                    Repeater {
                        model: 3
                        Rectangle {
                            width: 5
                            height: 5
                            radius: 2.5
                            x: index * 8
                            color: root.accent
                            opacity: 0.2

                            SequentialAnimation on opacity {
                                running: root.mood === "think"
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 160 }
                                NumberAnimation { from: 0.2; to: 1; duration: 300 }
                                NumberAnimation { from: 1; to: 0.2; duration: 300 }
                                PauseAnimation { duration: 300 }
                            }
                        }
                    }
                }

                // error: bubble with !
                Rectangle {
                    id: errorBubble
                    visible: root.reaction === "error"
                    x: root.width * 0.72
                    y: root.height * 0.08
                    width: 22
                    height: 22
                    radius: 8
                    color: root.danger
                    scale: root.reaction === "error" ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                    Text {
                        anchors.centerIn: parent
                        text: "!"
                        color: "#3b0910"
                        font.family: "Google Sans Flex"
                        font.pixelSize: 15
                        font.bold: true
                    }
                }
            }
        }
    }

    // ---------------- status label ----------------
    Rectangle {
        id: hint
        visible: root.hintVisible
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.hintBelow ? root.height + 6 : -30
        width: label.implicitWidth + 18
        height: 24
        radius: 12
        color: root.surface
        border.color: root.outline
        border.width: 1
        opacity: 0.96

        Text {
            id: label
            anchors.centerIn: parent
            text: root.hintText
            color: (root.busy || root.toolActive || root.reaction !== "") ? root.accent : root.textDim
            font.family: "Google Sans Flex"
            font.pixelSize: 11
        }
    }

    // ---------------- mouse ----------------
    // Single click is delayed so a double click does not toggle the chat twice.
    Timer {
        id: clickDelay
        interval: 260
        onTriggered: root.activate()
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: mouse.drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        drag.target: root
        drag.axis: Drag.XAndYAxis
        drag.minimumX: 0
        drag.maximumX: Math.max(0, root.parent ? root.parent.width - root.width : 0)
        drag.minimumY: 0
        drag.maximumY: Math.max(0, root.parent ? root.parent.height - root.height : 0)

        property bool moved: false
        property real lastX: 0

        onEntered: {
            root.wake();
            root.resetIdle();
        }

        onPressed: {
            moved = false;
            lastX = root.x;
            root.dragLean = 0;
            root.wake();
            root.resetIdle();
            wanderAnim.stop();
            root.wandering = false;
            root.wanderLean = 0;
        }

        onPositionChanged: {
            if (drag.active) {
                moved = true;
                const dx = root.x - lastX;
                lastX = root.x;
                root.dragLean = Math.max(-8, Math.min(8, root.dragLean * 0.55 + dx * 1.6));
                root.resetIdle();
            }
        }

        onReleased: mouse => {
            root.dragLean = 0;
            if (moved) {
                root.moved(root.x, root.y);
            } else if (mouse.button === Qt.RightButton) {
                root.historyRequest();
            } else {
                clickDelay.restart();
            }
            root.resetIdle();
        }

        onDoubleClicked: mouse => {
            if (mouse.button === Qt.LeftButton) {
                clickDelay.stop();
                root.doubleActivate();
            }
        }

        onCanceled: {
            clickDelay.stop();
            root.dragLean = 0;
            root.resetIdle();
        }
    }
}
