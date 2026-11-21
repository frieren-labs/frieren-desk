# opencode backend

## Invocation

`shell.qml` runs one process per message:

```bash
opencode run --format json \
  --model opencode-go/deepseek-v4.1-flash \
  --agent frieren \
  --session <id> \
  "<message>"
```

Details that matter:

- The binary is hardcoded as `~/.opencode/bin/opencode`.
- The working directory is `$HOME`.
- PATH starts with `~/.opencode/bin`, then `/usr/local/bin:/usr/bin:/bin`.
- `NO_COLOR=1` is set.
- stdin is closed with `exec "$0" "$@" < /dev/null`. Without this, opencode
  waits for EOF and the chat hangs.
- The session ID is optional. When present it keeps context across restarts.
- The model appears twice: `modelName` in `shell.qml` and `model:` in
  `opencode/agents/frieren.md`. Keep them in sync or make one the source of
  truth.

## Account setup

The provider is `modelName` before the slash (`opencode-go` by default).

- `opencode auth list --format json` is the source of truth. The shell parses
  it at startup, when the account dialog opens, and every 4 seconds while the
  dialog is open. It keeps `authStatus`, `authDetail` and the credential ids in
  memory, and saves only the connected bool as `auth` in `state.json`.
- Save key builds an `opencode auth import` payload in QML and writes it to the
  process stdin: a list with `id`, `integrationID`, `label`, `active` and
  `value: {type: "key", key: ...}`. Then it runs
  `opencode auth switch <provider> <id>` and verifies with another
  `auth list`.
- Only after the new credential is active does it log out older credentials
  with label `Frieren` or id prefix `cred_frieren_`, so repeated saves replace
  instead of piling up and a failed import never removes a working account.
- If the switch fails, it logs out the new credential and refreshes the status.
- `opencode auth login --method key` cannot take the key from `--answer`; it
  prompts on a TTY. That is why the pet imports instead of driving the prompt.
- Providers with OAuth or device flows use the dialog's terminal button, which
  opens `opencode auth login <provider>` in the first available emulator.
- An environment credential such as `OPENCODE_API_KEY` counts as connected.
- When the check says missing, `send()` opens the account dialog instead of
  spawning opencode. The chat also shows a banner until connected.
- The bool reaches the tray menu as `auth` in `state.json`.

## Event handling

Stdout is split by newline. `handleLine` ignores anything that is not a JSON
object and handles:

| `ev.type` | Payload | Effect |
| --- | --- | --- |
| `text` | `part.id`, `part.text` | Upserts an assistant message |
| `tool_use` or `tool` | `part.id`, `part.state` | Upserts a tool block |
| `error` | `error` | Shows a system message and `pet.react("error")` |

`partIndex` maps a `part.id` to a `ListModel` row. `upsertText` appends on the
first event and updates afterwards. `upsertTool` reads `state.input.command`,
`filePath`, `description` or `query`, plus `state.output`, `state.error` and
`state.status`.

Tool status drives the pose:

- `running` or `pending`: `toolActive = true`, which shows `cast`.
- `completed`: increments `toolCount` but leaves `toolActive` alone.
- `error`: triggers `pet.react("error")`.

That last point is a known weakness. `toolActive` is only reset by a later tool
status, `send()`, `stopAgent()` or `onExited`. A tool that never reports a final
status leaves the pet casting forever. If you touch this area, add a timeout or
derive the flag from the latest tool state.

## Exit handling

`onExited`:

- Clears `busy` and `toolActive`.
- Skips reactions when `stopping` is true.
- On code 0, plays the success reaction.
- On a non-zero code other than 130, adds a system message and plays the error
  reaction, unless an error event already did.

opencode exits 0 even when a tool failed, so success is not proof that the task
worked. Prefer the event stream when deciding the final mood.

## Stop and fresh races

`stopAgent()` sets `agent.running = false` and immediately clears `busy` and
`toolActive`, then appends `Stopped.` The process may take time to die, and
`onExited` can still arrive later.

`freshSession()` stops the agent, clears `chat`, resets `partIndex`, clears the
session ID and appends a greeting. If old stdout lines arrive after the clear,
they land in the new conversation.

The robust fix is a monotonically increasing run ID:

1. Increment it on every `send`, `stop` and `fresh`.
2. Capture it when starting the process.
3. Ignore `handleLine` and `onExited` when the captured run ID is not current.

Do not change stop or fresh without considering this.

## Errors and logs

- Stderr is logged only while `busy`. Errors after exit are lost.
- Quota errors can contain a large JSON blob. `showError` trims at the first
  `{` when the message is longer than 220 characters.
- Logs from the shell and tray helper go to stderr through `console.log`.
  Start `qs -c frieren` in the foreground to see them.

## Agent and permissions

The installed agent is `~/.config/opencode/agents/frieren.md`, copied from
`opencode/agents/frieren.md` by `install.sh`. `install.sh` refuses to overwrite
an existing agent unless called with `--force`.

The frontmatter denies a list of destructive shell patterns and secret reads.
This is a denylist, not a sandbox:

- The shell tool itself is allowed for everything else.
- A deny on `read` does not stop `cat ~/.ssh/id_ed25519` through the shell.
- Patterns miss many dangerous operations, for example shredding, moving home
  directories, stopping services, or piping remote scripts to interpreters.

Treat any change to the agent as a security change. Review the persona and the
permissions together.

## Adding an event type

1. Confirm the real shape with
   `opencode run --format json --agent frieren "..."` and inspect one line.
2. Add a branch in `handleLine`.
3. Add or extend an upsert helper.
4. Make sure the chat model schema still matches `MessageBubble.qml`.
5. Test success, tool error, stop and fresh.
