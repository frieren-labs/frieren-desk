# State, tray and IPC

## state.json

Path: `~/.local/state/frieren/state.json`. Override the state home with
`XDG_STATE_HOME` and the file moves accordingly.

`saveState()` writes the whole document to `state.json.tmp` and moves it into
place with `sh -c`, so readers never see a partial file.

| Key | Type | Written by | Read by | Meaning |
| --- | --- | --- | --- | --- |
| `x`, `y` | number | drag, wander, minimize | startup | Pet position |
| `session` | string | opencode events, fresh | startup | opencode session ID |
| `minimized` | bool | minimize, restore | startup, tray | Pet hidden to tray |
| `wander` | bool | tray, IPC | startup, tray | Autonomous movement |
| `sleep` | bool | tray, IPC | startup, tray | Sleep when idle |
| `blink` | bool | tray, IPC | startup, tray | Blinking |
| `log` | bool | tray, IPC | startup, tray | Activity log hook |
| `scale` | number | tray, IPC | startup, tray | 0.7 to 1.4 |
| `auth` | bool | auth check | tray | opencode account connected |
| `busy` | bool | busy changes | none | Snapshot for debugging |
| `chatOpen` | bool | chat changes | none | Snapshot for debugging |

`loadState()` clamps `scale`, restores position and session, and refuses to
place the pet above y=60 by resetting to the default corner.

`saveState()` reads the live `pet.x` and `pet.y` when the pet is not minimized.
After changing `root.petX` or `root.petY` programmatically, call
`root.placePet()` first, then save. Otherwise the previous live position is
written. The scale handler and `resetpos` follow this order.

Adding a setting requires all of: a `property` in `shell.qml`, a read in
`loadState`, a write in `saveState`, an entry in `tray.c`, and docs.

`auth` is different: it is runtime status, not a user setting. The account check
writes it, the tray reads it for the menu label, and `stateLoaded` gates the
first save. Without that gate, a fast auth check can write defaults over the
loaded session and position.

## History and the activity hook

- History lives in SQLite at `~/.local/state/frieren/frieren.db`, in the same
  file as the activity log. Tables: `conversations` (`id`, `title`,
  `created_at`, `updated_at`) and `messages` (`conversation_id`, `role`,
  `text`, `command`, `output`, `status`, `ts`). Up to 60 conversations and 150
  messages each; tool output is cut to 1500 characters.
- QML drives the `sqlite3` CLI. Schema, queries and JSON payloads go over the
  processes' stdin, and the writers set `.timeout 5000` (with WAL from the
  hook) so history saves and activity events can overlap.
- Key the conversation with `root.activeConvId`, not `root.sessionId`. opencode
  can replace the session id on the first event of a run, and
  `adoptSessionId()` renames the open row so the list does not duplicate.
- The chat is restored only when `state.json` has a session id that matches a
  stored conversation. A fresh session (empty id) starts with an empty chat.
- `history.json` from older installs is imported once at startup and renamed to
  `history.json.migrated`.
- `hooks/frieren-log.sh` receives one JSON event per line on stdin from
  `root.emitEvent()`. It appends the raw line to `events.jsonl` and inserts into
  `frieren.db` (`turns`, `tools`, `daily`). `install.sh` copies it to
  `~/.config/quickshell/frieren/hooks/`; editing the repo copy alone does not
  change the installed hook.
- `sqlite3` is a runtime requirement: the installer fails without it.

## Tray helper

`tray.c`, compiled to `frieren-tray`, registers
`org.kde.StatusNotifierItem-frieren` with the StatusNotifierWatcher and exposes
`com.canonical.dbusmenu` at `/MenuBar`.

It reads state on every layout request and watches the state file with a Gio
file monitor (a 500 ms mtime poll is the fallback). On change it emits
`LayoutUpdated` and `ItemsPropertiesUpdated`.
It writes nothing itself: every action calls `qs -c frieren ipc call frieren`.

### Menu IDs

| ID | Item | Action |
| --- | --- | --- |
| 1 | Show pet / Hide pet | `restore` or `minimize` |
| 2 | Open chat / Close chat | `toggle` |
| 4 | Stop | `stop`, enabled only while busy |
| 5 | Separator | none |
| 6 | Settings submenu | none |
| 7 | Wander | `wander toggle` |
| 8 | Sleep when idle | `sleep toggle` |
| 9 | Blink | `blink toggle` |
| 18 | Activity log | `log toggle` |
| 10 | Size submenu | none |
| 11 | Small | `scale 0.85` |
| 12 | Medium | `scale 1.0` |
| 13 | Large | `scale 1.15` |
| 14 | Reset position | `resetpos` |
| 15 | Separator | none |
| 16 | Quit | `quit` |
| 17 | Account / Setup account | `auth` |
| 19 | About | `about` |

Keep IDs stable. ID 3 (`New conversation`) was retired; do not reuse it for a
different item. `notify_state()` sends updates only for IDs 1, 2, 4, 7, 8, 9,
18, 11 to 13 and 17. Add new toggle or radio IDs to that list.

### Toggle type rules

DBusMenu defines exactly two values:

- `toggle-type: "checkmark"` with `toggle-state` 0 or 1.
- `toggle-type: "radio"` with `toggle-state` 0 or 1.

Quickshell maps any other string to no indicator and logs
`Unrecognized toggle type`. `"check"` is not valid, even though it looks
reasonable. This repository used `"check"` once and the menu showed no boxes.

`tray.c` sets `toggle-state` from `state.json`. If the checkmark does not
change after clicking:

1. Confirm the IPC call reaches the shell.
2. Confirm `state.json` changed.
3. Confirm the helper saw the mtime change.
4. Reopen the menu. Some clients cache properties.
5. Restart the helper if it is stale.

### Helper lifecycle

`shell.qml` starts the helper as a `Process`, so `qs` is its parent. The helper
calls `prctl(PR_SET_PDEATHSIG, SIGTERM)`, which makes the kernel terminate it
when `qs` dies. That avoids orphan icons without polling the IPC, and it also
covers a crash or a kill -9 of the shell.
If it crashes, the QML process does not restart it automatically. Reload the
shell or start the helper manually for now.

The fixed bus name makes a second helper exit with
`another tray helper is already running` instead of duplicating the icon.

Manual start, matching `shell.qml`:

```bash
~/.config/quickshell/frieren/frieren-tray \
  ~/.config/quickshell/frieren/assets/frieren-icon.png \
  ~/.config/quickshell/frieren/assets/frieren-icon-128.argb \
  ~/.config/quickshell/frieren/assets/frieren-icon-64.argb \
  ~/.config/quickshell/frieren/assets/frieren-icon-32.argb \
  ~/.local/state/frieren/state.json
```

## IPC

The handler target is `frieren`.

| Method | Arguments | Effect |
| --- | --- | --- |
| `toggle` | none | Open or close the chat, restore if minimized |
| `ask` | text | Open the chat and send text |
| `fresh` | none | New conversation |
| `stop` | none | Stop the current run |
| `hide` | none | Close the chat |
| `auth` | none | Open the OpenCode account dialog |
| `about` | none | Open the About dialog |
| `ping` | none | Return `pong` |
| `minimize` | none | Hide the pet to the tray |
| `restore` | none | Show the pet |
| `wander` | `toggle` or `true` or `false` | Set wandering |
| `sleep` | `toggle` or `true` or `false` | Set sleep when idle |
| `blink` | `toggle` or `true` or `false` | Set blinking |
| `log` | `toggle` or `true` or `false` | Set the activity log hook |
| `scale` | number | Set scale, clamped to 0.7 to 1.4 |
| `resetpos` | none | Move to the default corner |
| `quit` | none | Quit the shell |

Examples:

```bash
qs -c frieren ipc call frieren ping
qs -c frieren ipc call frieren ask "how much disk is free on /"
qs -c frieren ipc call frieren sleep toggle
```

## Adding a setting

1. Default in `shell.qml`.
2. Load in `loadState`, save in `saveState`.
3. Add the field to `State` defaults and `read_state` in `tray.c`.
4. Add a menu entry with a stable ID and a valid `toggle-type`.
5. Add it to the `dynamic_ids` list in `emit_state_changed`.
6. Add the action in `activate`.
7. Add an IPC method for script access.
8. Update `quickshell/frieren/README.md`.
9. Rebuild with `install.sh` and restart.

## Security notes

- The IPC socket belongs to the user session. Any process of the same user can
  call `ask` and trigger the agent.
- `tray.c` only passes fixed arguments to `qs`. Do not accept arbitrary text
  for the command line.
- `saveState()` passes the JSON payload as `$1`, not interpolated into the
  script, so quotes and newlines are safe.
- The account key stays in QML memory and reaches `opencode auth import` over
  its stdin. It must never appear in argv, `ps`, the state file or the logs.
