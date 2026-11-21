# Frieren · desktop pet

Chibi Frieren on the desktop with a chat bubble that talks to `opencode` and can
change the system. She also has a real system tray icon with a settings menu.

## Usage

- App menu: open **Frieren** (or run `~/.local/bin/frieren`), installed by
  `install.sh`. It starts the pet and opens the chat when she is closed, or
  toggles the chat when she is running.
- Drag her with the mouse: the position is saved in
  `~/.local/state/frieren/state.json`.
- Drop her on the top bar or the bottom dock to minimize her to the tray icon.
- Click the tray icon (or right-click it) to open the menu.
- Click the pet without dragging: opens or closes the chat.
- `SUPER + SHIFT + R`: opens the chat from anywhere.
- `Esc` or `✕`: closes the chat. `＋`: new conversation. `■`: stops the current run.
- The conversation keeps context across restarts: the opencode session ID is
  stored in the state file.

IPC:

```bash
qs -c frieren ipc call frieren toggle
qs -c frieren ipc call frieren ask "how much disk is free on /"
qs -c frieren ipc call frieren fresh
qs -c frieren ipc call frieren stop
qs -c frieren ipc call frieren hide
qs -c frieren ipc call frieren minimize
qs -c frieren ipc call frieren restore
qs -c frieren ipc call frieren wander toggle
qs -c frieren ipc call frieren sleep toggle
qs -c frieren ipc call frieren blink toggle
qs -c frieren ipc call frieren scale 1.15
qs -c frieren ipc call frieren resetpos
qs -c frieren ipc call frieren ping
qs -c frieren ipc call frieren quit
```

## Tray menu

`tray.py` registers a StatusNotifierItem with the watcher owned by the DMS bar
and exposes a DBusMenu:

- `Show / Hide pet`
- `Open / Close chat`
- `New conversation`
- `Stop` (enabled while opencode is busy)
- `Settings` → `Wander`, `Sleep when idle`, `Blink`, `Size` (small, medium,
  large), `Reset position`
- `Quit`

The helper needs `python3`, `python-dbus` and `python-gobject`. It starts with
the shell, uses a fixed bus name so reloads do not duplicate the icon, and exits
when the Frieren IPC stops answering.

## How it talks to the system

Each message runs:

```bash
opencode run --format json --model opencode-go/deepseek-v4.1-flash \
  --agent frieren --session <id> "<message>"
```

- It uses the auth already configured in opencode (`opencode auth list`). No API
  key is written in this config.
- JSON events are parsed in `shell.qml`: assistant text, tool calls (command and
  output, visible in the chat as a log) and errors.
- The agent lives in `~/.config/opencode/agents/frieren.md` and carries the
  denylist: `sudo`, `doas`, `su`, `rm -rf /`, `rm -rf ~`, `mkfs`, `dd of=/dev/*`,
  `shutdown`, `reboot`, `poweroff`, `| sh`, `| bash`, and secret reads
  (`~/.ssh`, `~/.gnupg`, `~/.aws`, `.env`, `*.pem`, `auth.json`).
- To change the model: edit `modelName` in `shell.qml` and `model` in the agent
  markdown, or ask the agent to use another provider.

## Animations

The six poses live in `assets/poses/` (`idle`, `think`, `cast`, `happy`, `sad`,
`sleep`) and are described by `poses.json`. QML picks a pose from the shell
state and cross-fades between them. On top of the pose it adds breathing,
bobbing, sway, blinking, hover lean, drag tilt, thought dots, a staff glow and
particles while a tool runs, a jump and sparkles on success, a shake and an
exclamation bubble on error, floating `z`s while sleeping, and wandering.

`PetSprite.qml` owns the state machine and the timers. The shell passes `busy`,
`toolActive`, `chatOpen`, `lookDir`, the animation toggles and the scale.

## Files

```
~/.config/quickshell/frieren/
├── shell.qml                  # windows, opencode backend, state, IPC
├── tray.py                    # StatusNotifierItem + DBusMenu helper
├── components/
│   ├── PetSprite.qml          # poses, animation, drag
│   ├── ChatPanel.qml          # chat bubble
│   └── MessageBubble.qml      # messages and tool blocks
├── assets/
│   ├── frieren-icon.png       # tray icon and chat avatar
│   ├── frieren-icon-*.argb    # raw icon buffers
│   └── poses/
│       ├── idle.png
│       ├── think.png
│       ├── cast.png
│       ├── happy.png
│       ├── sad.png
│       ├── sleep.png
│       └── poses.json
```

Autostart: a block at the end of `~/.config/hypr/hyprland.lua`
(`qs -c frieren -n`). The `-n` avoids duplicates.

## Technical notes

- Pet window: a fullscreen `PanelWindow` on the `Overlay` layer with
  `exclusionMode: Ignore` and `mask: Region { item: hitArea }`, so the rest of
  the desktop stays clickable. The position belongs to the item, not the window,
  so dragging does not loop with the compositor.
- The chat is a second, smaller `PanelWindow` placed next to the pet.
- The `stdin` of the process is closed with `< /dev/null`: if opencode sees an
  open pipe it waits for EOF and hangs.
- When opencode exits with a quota error, the message appears in the chat.
- The tray helper writes nothing on its own: it reads `state.json` for the menu
  checkmarks and calls the IPC for every action.
- State writes go to `state.json.tmp` and are moved into place, so the helper
  never reads a partial file.
- If the keyboard does not take focus when the chat opens, change it to
  `WlrKeyboardFocus.Exclusive` in `shell.qml` (it blocks the global keyboard
  while open).

## Stop / restart

```bash
python3 - <<'EOF'
import os, glob, signal
for p in glob.glob('/proc/[0-9]*/cmdline'):
    try:
        a = [x.decode() for x in open(p,'rb').read().split(b'\0') if x]
    except OSError:
        continue
    if len(a) >= 3 and a[0].endswith('/qs') and a[1:3] == ['-c','frieren']:
        os.kill(int(p.split('/')[2]), signal.SIGTERM)
EOF

qs -c frieren            # foreground, logs on stderr
qs -c frieren -d         # daemon
```

The tray helper exits by itself when the IPC stops answering. To rebuild the
poses or the icon, use `tools/slice_spritesheet.py` (Pillow) and
`tools/make_icon.sh` (ImageMagick, xxd, sed) from the repo.
