# Verification

Run the checks that match the change. Do not declare work done after only
reading the diff.

## Fast checks

```bash
# Python helper syntax
python3 -m py_compile quickshell/frieren/tray.py quickshell/frieren/auth.py

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

After changing `tray.py`, also restart the helper. A shell restart does it. To
restart only the helper, kill the `tray.py` process and start it manually using
the command in `state-tray-ipc.md`. The QML process does not restart it on its
own.

## State and tray

```bash
cat ~/.local/state/frieren/state.json
.opencode/skills/frieren-pet/scripts/tray-state.sh
```

The tray output must show `toggle-type: checkmark` for Wander, Sleep when idle
and Blink, and `toggle-type: radio` for Size. `check` is a bug.

The helper should be a child of `qs` and disappear within a second of
`qs -c frieren ipc call frieren quit`. It should not spawn periodic `qs ...
ping` children; idle CPU is zero and state changes arrive through the Gio file
monitor.

Toggle each item and confirm all three layers agree:

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
- A tool call shows a block with command and output.
- A tool error shows a red block and the sad pose.
- Stop mid-run shows `Stopped.` and returns to idle without a late success jump.
- New conversation clears the transcript and starts a fresh session.
- Close and reopen the chat. The transcript stays for the current shell session.
- Restart the shell. The session ID is reused, even though the transcript is
  empty.
- Escape closes the chat.

### Backend

- `ask` from IPC opens the chat and sends the text.
- Empty messages are ignored.
- A message sent while busy is rejected with a system notice.
- A missing or unauthenticated opencode shows a visible error, not a silent hang.

### Theme

- Change the DMS color mode and reopen the chat. Colors follow the theme.
- No component uses a hardcoded color outside the fallback theme.
- Fonts fall back cleanly when the DMS typography file is missing.

### Account

- With credentials, the tray shows `Account...` and the dialog shows
  `Connected` with the method labels.
- Without credentials (empty `XDG_DATA_HOME`, no `OPENCODE_API_KEY`), the tray
  shows `Setup account...`, the chat shows the banner, and sending a
  message opens the dialog instead of running opencode.
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
| Account says not connected | `auth.py status opencode-go`, `opencode auth list`, env vars |
| Key save fails | `opencode auth import`, `auth switch`, dialog message |
| Tray label never changes | `auth` in `state.json`, `notify_state` includes ID 17 |
| Pet stuck casting | `toolActive`, last tool status, late events |
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
