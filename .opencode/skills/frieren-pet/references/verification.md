# Verification

Run the checks that match the change. Do not declare work done after only
reading the diff.

## Fast checks

```bash
# Native tray build
cc -O2 -Wall -Wextra -o /tmp/frieren-tray quickshell/frieren/tray.c \
  $(pkg-config --cflags --libs gio-2.0)

# Shell scripts
bash -n .opencode/skills/frieren-pet/scripts/*.sh

# QML load and runtime logs, foreground
qs -c frieren
```

`qmllint` can catch generic QML issues, but it does not resolve Quickshell
imports in this project, so treat its output as a hint and not a gate.

## Restart and health

```bash
.opencode/skills/frieren-pet/scripts/restart.sh
.opencode/skills/frieren-pet/scripts/health.sh
```

`health.sh` checks IPC, state file and tray process. `restart.sh` asks the
running shell to quit through IPC, waits, terminates any stale `qs` instance for
this config by exact argv, and starts one instance with `-n` in daemon mode.
Do not replace it with a bare `qs -c frieren -d`: `quit` only stops the instance
that answers IPC, and duplicate instances share one state file and fight over
the pet position.

After changing `tray.c`, rebuild with `install.sh` and restart the shell. A
shell restart starts the new binary. To restart only the helper, kill the
`frieren-tray` process and start it manually using the command in
`state-tray-ipc.md`. The QML process does not restart it on its own.

## State and tray

```bash
cat ~/.local/state/frieren/state.json
.opencode/skills/frieren-pet/scripts/tray-state.sh
```

The tray layout is five plain entries (pet, chat, settings, about, quit).
Only the pet and chat labels update dynamically. `tray-state.sh` still queries
the backing setting IDs (7, 8, 9, 18, 11, 12, 13): the props must show
`toggle-type: checkmark` for Wander, Sleep when idle, Blink and Activity log,
and `toggle-type: radio` for Size. `check` is a bug. Those states are now
surfaced in the Settings window instead of tray submenus.

The helper should be a child of `qs` and disappear within a second of
`qs -c frieren ipc call frieren quit`. It should not spawn periodic `qs ...
ping` children; idle CPU is zero and state changes arrive through the Gio file
monitor. `frieren-tray` should sit at about 7 MB RSS; a much larger process
means a stale helper is still running.

Toggle each setting from the Settings window and confirm all three layers agree:

1. The IPC call succeeded.
2. `state.json` changed.
3. `tray-state.sh` shows the new state after reopening the menu.

## Manual matrix

### Pet

- Pet appears at the saved position.
- Hover wakes her and shows the hint.
- Click opens and closes the chat.
- Drag moves the pet and persists the new position.
- Dropping near the top bar or bottom dock minimizes to the tray.
- Restore returns her to a sane position.
- Idle for three minutes with sleep enabled: she sleeps, shows the `z` layer,
  and any hover wakes her.
- Disable sleep while asleep: she wakes immediately.
- Wander on: she moves every 25 to 60 seconds and avoids the bars.
- Wander off: she stays put.
- Blink on: she blinks. Blink off: no blink.
- Size small, medium and large all render inside the mask.

### Chat

- Send a message and see the assistant text stream in.
- A reply with Markdown shows a large heading, bold, bullets, a numbered list, a
  quote, inline code and a fenced code block with a language label.
- A long reply keeps following only while the list is at the end. Scroll up
  while text is streaming: the view must stay put and show `↓ Latest`.
- `↓ Latest` returns to the end and resumes following.
- Select text with the mouse in a reply, a tool block and a code block.
- Hover a reply and copy it. Copy a code block with its icon; the check mark
  appears and `wl-paste` returns the code.
- Copy a tool command with its icon.
- A tool call shows a block with command and output.
- A tool error shows a red block and the sad pose.
- Stop mid-run shows `Stopped.` and returns to idle without a late success jump.
- New conversation clears the transcript and starts a fresh session.
- Close and reopen the chat. The transcript stays for the current shell session.
- `≡` lists past conversations newest first with question count and time.
- Open an older conversation: its messages appear and the next question
  continues that opencode session (`state.json` session changes).
- Delete a conversation: it leaves the list; deleting the open one starts a
  fresh conversation.
- Restart the shell. The saved session's transcript is restored from
  `frieren.db`. After `+` (fresh), a restart starts empty.
- Escape closes the chat.

### Backend

- `ask` from IPC opens the chat and sends the text.
- Empty messages are ignored.
- A message sent while busy is rejected with a system notice.
- A missing or unauthenticated opencode shows a visible error, not a silent hang.

### History and activity log

- After a turn, `sqlite3 ~/.local/state/frieren/frieren.db
  "select id, title from conversations;"` shows the conversation and
  `select role from messages where conversation_id='<id>' order by id;` shows
  the transcript. A refused run still keeps the question.
- Restart the shell: the saved session's transcript comes back from the
  database, not from a JSON file.
- If `history.json` exists from an older install, it is imported once and
  renamed to `history.json.migrated`; rows are not duplicated on the next start.
- `events.jsonl` gains one `turn` line per question. A stopped run has
  `exit_code: -1` and `error: "stopped"`.
- `sqlite3 ~/.local/state/frieren/frieren.db "select prompt, ok, tools_failed from turns;"`.
- A failed tool sets `ok = 0` on its turn even when opencode exits 0.
- Settings → `Data` → Activity log off stops new `turns`/`tools` rows; history
  and the existing files stay.

### Theme

- Change the DMS color mode and reopen the chat. Colors follow the theme.
- No component uses a hardcoded color outside the fallback theme.
- Fonts fall back cleanly when the DMS typography file is missing.

### About

- Tray → `About` opens the card with the happy pose, project description,
  author, repository link and MIT license link.
- The repository and license links open in the browser.
- Escape and `✕` close it; the rest of the desktop stays clickable (mask).

### Settings

- Tray → `Settings` opens the large window with `Pet`, `Sound & voice`,
  `Data` and `Model & account` tabs. `qs -c frieren ipc call frieren settings
  sound` opens it directly on a tab.
- Pet tab toggles wander, sleep and blink, picks Small / Medium / Large and
  resets the position. Each change lands in `state.json` and
  `settings.json`.
- Sound tab toggles UI sounds and voice replies, lists the downloaded voices
  with the current one checked, picks the volume preset and speaks a test
  line. With no voices installed, the empty hint names `frieren-voice list`.
- Data tab toggles the activity log and Discord alerts, posts a test embed
  and runs a database backup.
- The account tab embeds the same `AuthDialog` as the standalone window:
  status, model picker, key import and terminal login all behave the same.
- Escape and `✕` close it; the rest of the desktop stays clickable (mask).

### Account

- With credentials, the Settings account tab shows `Connected` with the
  method labels.
- Without credentials (empty `XDG_DATA_HOME`, no `OPENCODE_API_KEY`), the chat
  shows the banner, and sending a message opens the account dialog instead
  of running opencode.
- Saving a key clears the field, shows `Key saved.`, flips the status to
  `Connected`, removes the banner and writes `auth: true` to `state.json`.
- Saving again replaces the previous `Frieren` credential, so
  `opencode auth list` has only one.
- Terminal login opens a terminal and the status updates without reopening the
  dialog (4 second poll).
- The key never appears in `ps`, `state.json` or the shell logs.

## Failure diagnosis

| Symptom | Check |
| --- | --- |
| No pet | `qs -c frieren` foreground logs, screen size, `placePet` |
| Chat does not open | `toggle` IPC, `chatOpen`, monitor geometry |
| Chat opens but no reply | `opencode` in PATH, auth, `opencode auth list`, stdin closed |
| Account says not connected | `opencode auth list`, env vars, QML auth logs |
| Key save fails | `opencode auth import`, `auth switch`, dialog message |
| Tray label never changes | `minimized` / `chatOpen` in `state.json`, `ItemIsMenu` client refresh |
| Settings window does not open | `settings` IPC, `settingsOpen`, monitor geometry |
| Pet stuck casting | `toolActive`, last tool status, late events |
| Menu checkboxes missing | `toggle-type` values, Quickshell warning log |
| Stale text after fresh | late stdout from the old process, run ID guard |
| Tray icon missing | helper process, StatusNotifierWatcher, DMS tray settings |
| Orphan tray icon | helper PPID is not `qs`; parent death signal, restart helper |
| Menu checkboxes missing | `toggle-type` values, Quickshell warning log |
| Checkmarks stale | state write, mtime, `notify_state`, reopen menu |
| Wrong position after restart | `state.json`, `lastGoodX/Y`, `petY < 60` reset |
| Desktop clicks blocked | `mask` region and `hitArea` size |

## Cleanup

Do not leave test processes, temporary agents or modified state behind. If you
lowered the sleep timeout or changed a default for testing, restore it. If you
changed `state.json` by hand, leave the pet in a valid position.
