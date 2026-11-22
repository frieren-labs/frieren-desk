# Frieren · desktop pet

Chibi Frieren on the desktop with a chat bubble that talks to `opencode` and can
change the system. She also has a real system tray icon with a settings menu.

## Usage

- App menu: open **Frieren** (or run `~/.local/bin/frieren`), installed by
  `install.sh`. It starts the pet and opens the chat when she is closed, or
  toggles the chat when she is running.
- Account: tray icon → **Setup account** when not connected, **Account**
  when connected (see below). The chat shows a banner while the account is not
  connected.
- Drag her with the mouse: the position is saved in
  `~/.local/state/frieren/state.json`.
- Drop her on the top bar or the bottom dock to minimize her to the tray icon.
- Click the tray icon (or right-click it) to open the menu.
- Click the pet without dragging: opens or closes the chat.
- `SUPER + SHIFT + R`: opens the chat from anywhere.
- `Esc` or `✕`: closes the chat. `＋`: new conversation. `■`: stops the current run.
- The chat renders Markdown: headings, lists, quotes, inline code, fenced code
  blocks and links. Code blocks have their own box with a copy button.
- Click and drag over any message to select it. A copy button appears on hover
  for the whole reply, and every code block and command has its own copy icon.
- `≡` opens the history of past conversations. Click one to reopen it, `✕`
  deletes it. Scrolling up while she writes no longer drags the view back down;
  `↓ Latest` returns to the end.
- Tray → **About** shows the project, the author, the happy pose, the repository
  and the MIT license.
- The conversation keeps context across restarts: the opencode session ID is
  stored in the state file, and its messages are restored from the local
  database.

IPC:

```bash
qs -c frieren ipc call frieren toggle
qs -c frieren ipc call frieren ask "how much disk is free on /"
qs -c frieren ipc call frieren fresh
qs -c frieren ipc call frieren stop
qs -c frieren ipc call frieren hide
qs -c frieren ipc call frieren auth
qs -c frieren ipc call frieren about
qs -c frieren ipc call frieren minimize
qs -c frieren ipc call frieren restore
qs -c frieren ipc call frieren wander toggle
qs -c frieren ipc call frieren sleep toggle
qs -c frieren ipc call frieren blink toggle
qs -c frieren ipc call frieren log toggle
qs -c frieren ipc call frieren scale 1.15
qs -c frieren ipc call frieren resetpos
qs -c frieren ipc call frieren ping
qs -c frieren ipc call frieren quit
```

## Tray menu

`tray.c` is compiled to `frieren-tray` by `install.sh` and registers a
StatusNotifierItem with the watcher owned by the DMS bar. It exposes a
DBusMenu:

- `Show / Hide pet`
- `Open / Close chat`
- `Stop` (enabled while opencode is busy)
- `Setup account` when not connected, `Account` when connected
- `Settings` → `Wander`, `Sleep when idle`, `Blink`, `Activity log`, `Size`
  (small, medium, large), `Reset position`
- `About` (project, author, happy Frieren, repository and MIT license)
- `Quit`

The helper uses only GIO/GDBus, starts with the shell, and uses a fixed bus name
so reloads do not duplicate the icon. State changes are watched with a Gio file
monitor, and the helper takes a parent death signal, so it exits with the shell
instead of polling its IPC. It sits at about 7 MB RSS with zero idle CPU.

## OpenCode account

A fresh install has no opencode credentials, so the first message would fail.
The pet covers that setup:

- Tray menu → **Setup account** (or **Account** when connected) opens the
  account dialog. The chat banner opens the same dialog.
- **Save key**: paste the API key for the provider in `modelName`
  (`opencode-go` by default). The dialog sends the key to `opencode auth import`
  over stdin and then runs `opencode auth switch`, with the label `Frieren`.
  Repeated saves replace the previous Frieren credential.
- **Terminal login**: opens the first available terminal emulator
  (`xdg-terminal-exec`, foot, kitty, alacritty, ghostty, wezterm, konsole,
  gnome-terminal or xterm) and runs `opencode auth login <provider>`, which
  covers OAuth and device flows such as GitHub Copilot.
- **Check** re-reads `opencode auth list --format json`. The dialog also polls
  every 4 seconds while it is open, so a terminal login shows up on its own.

The status is also saved as `auth` in `state.json`, which drives the tray label.
An `OPENCODE_API_KEY` environment variable counts as a connection, so users who
authenticate through the environment do not need to paste a key.

The pet never stores the key: it goes over stdin to `opencode auth import`, and
opencode keeps its own credential store. The key is not passed in argv.

## How it talks to the system

Each message runs:

```bash
opencode run --format json --model opencode-go/deepseek-v4.1-flash \
  --agent frieren --session <id> "<message>"
```

- It uses the opencode account configured from the account dialog, from
  `opencode auth login`, or from the environment. No API key is written in this
  config.
- JSON events are parsed in `shell.qml`: assistant text, tool calls (command and
  output, visible in the chat as a log) and errors.
- The agent lives in `~/.config/opencode/agents/frieren.md` and carries the
  denylist: `sudo`, `doas`, `su`, `rm -rf /`, `rm -rf ~`, `mkfs`, `dd of=/dev/*`,
  `shutdown`, `reboot`, `poweroff`, `| sh`, `| bash`, and secret reads
  (`~/.ssh`, `~/.gnupg`, `~/.aws`, `.env`, `*.pem`, `auth.json`).
- To change the model: edit `modelName` in `shell.qml` and `model` in the agent
  markdown, or ask the agent to use another provider.

## History and activity log

Both live in `~/.local/state/frieren/frieren.db` (SQLite; the `sqlite3` CLI is
required). The chat talks to it through `sqlite3`, so QML does not need a
database driver.

History:

- `conversations` keeps the last 60 conversations (`id`, `title`, `created_at`,
  `updated_at`). `messages` keeps up to 150 messages per conversation (`role`,
  `text`, `command`, `output`, `status`, `ts`). Only conversations with at
  least one question are stored.
- On startup the chat reopens the conversation of the saved opencode session.
  A fresh conversation (no session id yet) starts empty.
- `≡` lists every conversation with its first question, how many questions it
  has and when it was last used. Opening one switches the opencode session, so
  the next message continues that conversation.
- `history.json` from older versions is imported once and renamed to
  `history.json.migrated`.

Activity log (for a dashboard):

- Every finished turn and every finished tool call is sent to
  `hooks/frieren-log.sh` over stdin. The hook appends the raw JSON line to
  `~/.local/state/frieren/events.jsonl` and writes the same row to
  `frieren.db`:

  | Table / view | Columns |
  | --- | --- |
  | `conversations` | `id`, `title`, `created_at`, `updated_at` |
  | `messages` | `conversation_id`, `role`, `text`, `command`, `output`, `status`, `ts` |
  | `turns` | `ts`, `session`, `prompt`, `duration_ms`, `exit_code`, `ok`, `tools_total`, `tools_failed`, `error`, `model` |
  | `tools` | `ts`, `session`, `tool`, `command`, `status`, `ok`, `duration_ms` |
  | `daily` (view) | `day`, `turns`, `ok_turns`, `ok_pct`, `avg_ms`, `tool_failures` |

- `ok` is `exit_code = 0` and no failed tool and no error event. A stopped run
  is recorded with `exit_code = -1` and `error = "stopped"`.
- Disable the activity rows with tray → `Settings` → `Activity log`, or
  `qs -c frieren ipc call frieren log false`. History keeps working.
- `events.jsonl` grows with every event and is never rotated; delete it whenever
  you want to start over. `frieren.db` is independent and safe to keep.

```bash
# success rate per day
sqlite3 ~/.local/state/frieren/frieren.db "select * from daily order by day desc limit 14;"

# slowest turns
sqlite3 ~/.local/state/frieren/frieren.db \
  "select prompt, duration_ms from turns order by duration_ms desc limit 10;"

# stored conversations
sqlite3 ~/.local/state/frieren/frieren.db \
  "select id, title, updated_at from conversations order by updated_at desc;"
```

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
├── tray.c                     # native StatusNotifierItem + DBusMenu helper
├── frieren-tray               # compiled by install.sh (not in git)
├── hooks/
│   └── frieren-log.sh         # activity hook (JSONL + optional SQLite)
├── components/
│   ├── PetSprite.qml          # poses, animation, drag
│   ├── ChatPanel.qml          # chat bubble, scroll lock, history toggle
│   ├── MessageBubble.qml      # messages and tool blocks
│   ├── MarkdownText.qml       # Markdown blocks, code boxes, copy buttons
│   ├── CopyButton.qml         # clipboard button with a check mark
│   ├── HistoryPanel.qml       # list of past conversations
│   ├── AboutDialog.qml        # project, author, repository and license
│   └── AuthDialog.qml         # OpenCode account dialog
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
- The account dialog is a third fullscreen `PanelWindow` masked to the card. It
  polls the account status every 4 seconds while open, so terminal logins are
  picked up without reopening it.
- The About dialog is a fourth masked window, opened from the tray. It shows
  the happy pose, the author, the repository and the MIT license, and closes
  with Escape or its `✕`.
- The `stdin` of the process is closed with `< /dev/null`: if opencode sees an
  open pipe it waits for EOF and hangs.
- When opencode exits with a quota error, the message appears in the chat.
- The tray helper writes nothing on its own: it reads `state.json` for the menu
  checkmarks and calls the IPC for every action. It is event-driven: a Gio file
  monitor replaces the state poll, and there is no periodic IPC ping. Idle CPU
  is effectively zero; the 30 second re-register timer is the only periodic
  wakeup.
- State writes go to `state.json.tmp` and are moved into place, so the helper
  never reads a partial file.
- Chat history uses SQLite (`frieren.db`). SQL and JSON payloads go over
  `sqlite3` stdin, so long conversations never hit the argv limit. A
  `busy_timeout` covers concurrent writes from the activity hook.
- The chat list follows the end only while it is already at the end. Scrolling
  up sets `follow = false`; streaming text then grows the content without
  moving the view, and `↓ Latest` restores the lock. A `contentY` decrease
  caused by the first layout or a window resize is ignored.
- Markdown is parsed in `MarkdownText.qml` because Qt has no Markdown document.
  Fenced code blocks become a monospace box with a copy button; prose uses
  Qt's rich text subset. Text is selectable because the blocks are read-only
  `TextEdit` items (`Text` has no mouse selection in Qt 6).
- Copying uses `Quickshell.clipboardText`, so it works under any Wayland
  compositor without `wl-copy`.
- `MessageBubble.qml` keeps the full reply copy button in the delegate's right
  margin, so it never covers the text and does not reserve height.
- If the keyboard does not take focus when the chat opens, change it to
  `WlrKeyboardFocus.Exclusive` in `shell.qml` (it blocks the global keyboard
  while open).

## Stop / restart

```bash
ps -eo pid=,args= | awk '$2 ~ /(^|\/)qs$/ && $3 == "-c" && $4 == "frieren" { print $1 }' \
  | while read -r pid; do kill "$pid"; done

qs -c frieren            # foreground, logs on stderr
qs -c frieren -d         # daemon
```

The tray helper is a child of `qs` and exits with it (parent death signal). To
rebuild the icon, use `tools/make_icon.sh` (ImageMagick, xxd, sed) from the
repo. The pose PNGs are checked in; edit them directly.
