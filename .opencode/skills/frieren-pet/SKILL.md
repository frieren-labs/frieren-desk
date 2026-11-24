---
name: Frieren Pet
description: Work on the Frieren desktop pet in this repository. Use when changing the pet sprite, poses, animations, chat panel, opencode backend, tray menu, IPC, state.json, theme integration, or the install scripts under quickshell/frieren, tools or hypr.
---

# Frieren Pet

A chibi Frieren desktop pet for Hyprland built on Quickshell. It talks to
opencode through the `frieren` agent, runs system commands, animates six poses,
and exposes a StatusNotifierItem tray menu written in C.

This skill is project-local. It encodes the invariants that the generic QML
skills cannot know.

## Read first

1. `references/architecture.md` for the file map, windows and data flow.
2. `references/poses-and-animation.md` before touching `PetSprite.qml`, poses or timers.
3. `references/state-tray-ipc.md` before changing state, `tray.c` or IPC.
4. `references/opencode-backend.md` before changing the process, events, sessions or agent files.
5. `references/verification.md` before declaring a change done.

## Hard rules

- Code, comments, docs, commit messages and PR text in English.
- No em dashes (U+2014). Use periods, commas, colons, parentheses, hyphens or `·`.
- Keep QML components in `quickshell/frieren/components/` and the runtime state
  in `~/.local/state/frieren/state.json`.
- Do not hardcode colors or fonts in QML. Use the `theme` object passed by
  `shell.qml`, which reads DMS matugen colors and typography with fallbacks.
- DBusMenu `toggle-type` accepts only `checkmark` or `radio`. `check` is invalid
  and renders no indicator at all.
- Treat the agent denylist in `opencode/agents/frieren.md` as a guardrail, not a
  sandbox. Do not add `sudo`, disk formatting, shutdown or secret reads.
- Do not reformat files outside the change.

## Change map

| Task | Touch these files |
| --- | --- |
| Pet behavior, timers, new pose | `components/PetSprite.qml`, `assets/poses/poses.json`, `assets/poses/*.png` |
| Chat UI | `components/ChatPanel.qml`, `components/MessageBubble.qml`, `components/MarkdownText.qml`, `components/HistoryPanel.qml`, `components/CopyButton.qml` |
| Conversation history | `shell.qml` (`saveHistory`, `requestConversation`, `adoptSessionId`, `applyHistoryList`, `migrateLegacyHistory`), `components/HistoryPanel.qml` |
| Activity log / dashboard | `shell.qml` (`emitEvent`, `logTurn`), `hooks/frieren-log.sh` |
| Backend, events, sessions | `shell.qml` (`send`, `handleLine`, `upsertTool`, `Process agent`) |
| OpenCode account | `shell.qml` (auth properties and processes), `components/AuthDialog.qml`, `tray.c` |
| About dialog | `components/AboutDialog.qml`, `shell.qml` (`aboutWin`, IPC `about`), `tray.c` |
| State or settings | `shell.qml` (`loadState`, `saveState`, `statePath`), `tray.c` |
| Tray menu | `tray.c`, `.opencode/skills/frieren-pet/references/state-tray-ipc.md` |
| IPC | `shell.qml` (`IpcHandler`), `quickshell/frieren/README.md` |
| Theme | `shell.qml` (`theme`, `applyDmsColors`, `applyDmsType`) |
| New pose art | `assets/poses/*.png`, `assets/poses/poses.json`, `README.md` |
| Install or launch | `install.sh`, `hypr/frieren.lua` |

## Recipes

### Add a tray setting

1. Add the property and default in `shell.qml`.
2. Load and save it in `loadState` and `saveState`.
3. Add an entry and a stable ID in `tray.c`, using the `checkmark` toggle type
   for booleans and `radio` for exclusive choices.
4. Add the action in `_activate`.
5. Add an IPC method if scripts should change it.
6. Update `quickshell/frieren/README.md`.
7. Run `scripts/tray-state.sh` and confirm `toggle-type` and `toggle-state`.

### Add an IPC method

1. Add a function under `IpcHandler` in `shell.qml`.
2. Keep the name short. Existing methods: `toggle`, `ask`, `fresh`, `stop`,
   `hide`, `auth`, `ping`, `minimize`, `restore`, `wander`, `sleep`, `blink`,
   `scale`, `resetpos`, `quit`.
3. Document it in `quickshell/frieren/README.md` and in `references/state-tray-ipc.md`.
4. Test with `qs -c frieren ipc call frieren <method>`.

### Add or change a pose

1. Add or replace the affected 228x256 PNG in `assets/poses/`. The source sheet
   in `assets/frieren-sheet.png` is kept as art reference; there is no slicing
   script in the repo.
2. Follow `references/poses-and-animation.md` for the `poses.json` schema and
   update the file, eyes, skin and glow entries.
3. Update the `mood` mapping in `PetSprite.qml` and the pose table in `README.md`.
4. Update `assets/poses-preview.png` if the README image should change.
5. Verify the eye rectangles and the staff glow point on screen.

### Change the chat

- `MessageBubble.qml` renders four roles: `user`, `assistant`, `tool` and `system`.
- `MarkdownText.qml` is the only Markdown renderer: fenced code blocks become a
  monospace box with a copy button, prose uses Qt's rich text subset. Qt has no
  Markdown document.
- Keep text selectable: use a read-only `TextEdit` with `selectByMouse`.
  `Text` has no mouse selection in Qt 6.
- Copy actions use `Quickshell.clipboardText`; do not depend on `wl-copy`.
- The scroll lock lives in `ChatPanel.qml` (`list.follow`). Never add an
  unconditional `positionViewAtEnd` on count or content height: it fights the
  user when they scroll up.
- The input is a single-line `TextInput`. Multi-line support needs a new design.
- Do not block the whole panel while `busy`; only the input is disabled.
- `HistoryPanel.qml` receives `conversations` and emits `open` / `remove`.
  Opening a conversation switches the opencode session.
- History is stored in SQLite, in the same `frieren.db` as the activity log.
  QML drives the `sqlite3` CLI and sends SQL over stdin. `sqlite3` is a runtime
  requirement (`install.sh` checks it).

### Add a slash command

A new `/cmd` touches every layer; missing one leaves it half-wired:

1. `handleSlash()` in `shell.qml`: parse and act. Keep the handler pure
   enough for the `qmllint` baseline.
2. `/help` text in `handleSlash()`: same line lists every command.
3. `slashCommands` in `components/ChatPanel.qml`: the `cmd` plus a short
   `desc`, or typing `/` never suggests it.
4. Popup budget in `ChatPanel.qml`: `slashPopup` height caps visible rows
   and `slashList.positionViewAtIndex` follows keyboard navigation. New rows
   push older ones below the fold; verify with `/` and arrow keys.
5. IPC in `shell.qml` (`IpcHandler`) when scripts or the tray should call it.
6. Tray in `tray.c` when it needs a menu entry (stable ID, valid toggle type).
7. Docs in the same change: `quickshell/frieren/README.md` slash list plus
   `site/index.md` (commands, tray menu, settings keys) when they mirror it.

### Add an activity event

1. Call `root.emitEvent({ event: "name", ts: new Date().toISOString(), ... })`.
2. Add one `INSERT ... SELECT` to `hooks/frieren-log.sh`, guarded by
   `json_extract('$json', '$.event') = 'name'`.
3. Create the table with `CREATE TABLE IF NOT EXISTS`, and add a dashboard view
   if the event deserves one.
4. Reinstall so the hook reaches `~/.config/quickshell/frieren/hooks/`.
5. Check `events.jsonl` and `sqlite3 ~/.local/state/frieren/frieren.db`.

## Verification

Restart, then run the health check:

```bash
.opencode/skills/frieren-pet/scripts/restart.sh
.opencode/skills/frieren-pet/scripts/health.sh
```

Manual checklist and failure diagnosis: `references/verification.md`.

## Known pitfalls

- Late lines from a stopped or replaced opencode process can leak into a new
  conversation. See `references/opencode-backend.md` before changing `stop`,
  `fresh` or `handleLine`.
- `toolActive` must be cleared even when a tool never reports a final state.
- `Text` cannot be selected with the mouse. Use read-only `TextEdit`; code blocks
  and the tool log are their own copies, not `Text.PlainText`.
- `history.json` is gone: conversations and messages live in `frieren.db`
  (`conversations`, `messages`). The old file is imported once and renamed to
  `history.json.migrated`.
- History is keyed by `activeConvId`. If you set `sessionId` directly instead
  of calling `adoptSessionId()`, the open conversation duplicates.
- SQL and JSON payloads for history go over `sqlite3` stdin, never argv.
- The activity hook lives at the installed path, not the repo path. Editing
  `hooks/frieren-log.sh` requires `install.sh` before it runs.
- `restoreChatFromHistory()` only reopens the saved session. A fresh session
  must stay empty.
- Qt sets a bogus `contentY` during the first hidden layout. The scroll lock
  must ignore `contentY` decreases while the list height changes, or the chat
  shows `↓ Latest` immediately.
- Animations and timers keep running while the pet is minimized unless you
  gate them.
- Wandering falls back to `idle` because there is no `walk` pose yet.
- `lookDir` only leans the body. The sprite is not mirrored.
- `saveState()` stores the live pet position, not `petX` and `petY`. After a
  programmatic move, call `placePet()` before saving or the old position wins.
- The tray helper polls `state.json` by mtime. If a setting does not update in
  the menu, check that the state file was actually written and that the menu
  revision changed.
- The pet window uses a transparent fullscreen overlay plus a mask. Never
  remove `mask: Region { item: hitArea }` or the whole desktop stops receiving
  clicks.
- The account check runs at startup and can finish before `state.json` loads.
  Do not save state from the auth path until `stateLoaded` is true or the
  session and position get overwritten with defaults.
- The account flow keeps the key in QML memory and sends it to
  `opencode auth import` over stdin. It must never appear in argv, state.json or
  the logs.
- `tray.c` is the only tray helper and must stay on GIO/GDBus. `install.sh`
  compiles it and fails if the compiler or the gio headers are missing; there is
  no script fallback.
