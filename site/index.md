---
layout: default
title: Frieren Desk, a chibi pet that runs your system
---

<div class="hero">
  <div class="hero-bg" style="background-image: url('{{ '/assets/img/hero-bg.jpg' | relative_url }}')" role="img" aria-label="Frieren looking over a valley from a tower"></div>
  <div class="hero-veil" aria-hidden="true"></div>
  <video class="hero-video" src="{{ '/assets/overlay/birds.mp4' | relative_url }}" muted loop playsinline preload="auto" aria-hidden="true"></video>
  <div class="hero-inner" markdown="1">
  <h1>Frieren Desk<br><span class="gold">chat with her, she casts the spells</span></h1>
  <p class="hero-lede">A chibi Frieren lives on your desktop. Click her to chat with
  <strong>opencode</strong>: she reads files, edits code and runs commands, then reacts
  to what happens (thinking, casting, success, error, sleep).</p>

  <div class="cta-row">
    <a class="btn" href="#install">Summon her</a>
    <a class="btn btn-ghost" href="https://github.com/frieren-labs/frieren-desk">View source</a>
  </div>

  <div class="hud" aria-label="Requirements">
    <span>Hyprland <b>ready</b></span>
    <span>Quickshell <b>0.3+</b></span>
    <span>opencode <b>v2</b></span>
    <span>Qt 6 <b>ok</b></span>
    <span>sqlite3 <b>ok</b></span>
  </div>

  <figure class="install-rune">
    <figcaption><span>$ quick cast</span><button class="copy-btn" data-copy="install-cmd">copy</button></figcaption>
    <pre id="install-cmd"><code>curl -fsSL https://raw.githubusercontent.com/frieren-labs/frieren-desk/main/install.sh | bash</code></pre>
  </figure>
  </div>
</div>

<hr class="divider">

<div class="page">

<section id="how-it-works" markdown="1">
<img class="deco" src="{{ '/assets/img/poses/think.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## How it works

Every message you send runs through opencode with the Frieren agent:

```bash
opencode run --format json --model opencode-go/deepseek-v4.1-flash \
  --agent frieren --session "<id>" "<message>"
```

The shell parses the JSON events (assistant text, tool calls, errors) and picks a
pose for each moment. The conversation keeps context across restarts: the opencode
session id is stored locally and messages live in a SQLite database.

<div class="card-grid">
  <div class="card">
    <div class="card-icon" aria-hidden="true">💬</div>
    <h3>Chat bubble</h3>
    <p>Click the pet to open it. Markdown replies, selectable text, copy buttons on replies and code blocks, slash-command completion.</p>
  </div>
  <div class="card">
    <div class="card-icon" aria-hidden="true">🔔</div>
    <h3>Real tray icon</h3>
    <p>A native StatusNotifier helper (<code>tray.c</code>, compiled by the installer) with a short menu (pet, chat, settings, about, quit). About 7 MB RSS, zero idle CPU.</p>
  </div>
  <div class="card">
    <div class="card-icon" aria-hidden="true">🚶</div>
    <h3>Wandering pet</h3>
    <p>She breathes, blinks, bobs, leans toward your cursor and wanders on her own. Drop her on the top bar or bottom dock to minimize her.</p>
  </div>
  <div class="card">
    <div class="card-icon" aria-hidden="true">🔊</div>
    <h3>Voice replies</h3>
    <p>Optional spoken answers through Piper, espeak-ng or spd-say, plus UI sounds and desktop notifications for long turns. Opt in to mirror them to Discord as embeds (see below).</p>
  </div>
</div>

</section>

<section id="poses" markdown="1">
<img class="deco deco-left" src="{{ '/assets/img/poses/celebrate.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## Moods and poses

QML cross-fades between hand-drawn poses. Extra animation layers add breathing,
thought dots, a staff glow, casting particles, a victory jump, an error shake
and floating `z`s while she sleeps.

| Pose | When it shows | Chat line |
| --- | --- | --- |
| `idle` | waiting, or wandering around | `ask me something` |
| `think` | opencode is reasoning | `thinking...` |
| `cast` | a tool is running | `casting a spell...` |
| `reading` | a read-like tool is running | `reading...` |
| `happy` | a task finished, or she wakes up | `done` |
| `celebrate` | third clean turn in a row | `amazing!` |
| `sad` | an error came back | `oops...` |
| `sleep` | idle for a while with sleep enabled | `zzz...` |

</section>

<section id="gallery" markdown="1">
<img class="deco" src="{{ '/assets/img/poses/happy.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## In action

Real screenshots from a running session.

<div class="gallery" markdown="1">

<figure>
  <img src="{{ '/assets/img/shot-pet.png' | relative_url }}" alt="Pet on the desktop" loading="lazy">
  <figcaption>On the desktop: click to chat, double-click for a fresh conversation, right-click for history.</figcaption>
</figure>

<figure>
  <img src="{{ '/assets/img/shot-chat.png' | relative_url }}" alt="Chat with markdown and copy buttons" loading="lazy">
  <figcaption>Markdown replies, selectable text, copy buttons, slash-command completion.</figcaption>
</figure>

<figure>
  <img src="{{ '/assets/img/shot-stats.png' | relative_url }}" alt="Activity panel" loading="lazy">
  <figcaption>Activity panel: turns, success rate and average time per day.</figcaption>
</figure>

<figure>
  <img src="{{ '/assets/img/shot-settings.png' | relative_url }}" alt="Settings window, Pet tab" loading="lazy">
  <figcaption>Settings window: Pet, Sound & voice, Data and Model & account tabs.</figcaption>
</figure>

<figure>
  <img src="{{ '/assets/img/shot-settings-voice.png' | relative_url }}" alt="Settings window, Sound and voice tab" loading="lazy">
  <figcaption>Sound & voice tab: UI sounds, installed voices with the current one checked, volume presets.</figcaption>
</figure>

<figure>
  <img src="{{ '/assets/img/shot-settings-data.png' | relative_url }}" alt="Settings window, Data tab" loading="lazy">
  <figcaption>Data tab: activity log, Discord alerts toggle with test embed, plus backup.</figcaption>
</figure>

<figure>
  <img src="{{ '/assets/img/shot-auth.png' | relative_url }}" alt="Account dialog" loading="lazy">
  <figcaption>Account dialog: API key or terminal login, plus the model picker.</figcaption>
</figure>

</div>

</section>

<section id="notifications" markdown="1">
<img class="deco" src="{{ '/assets/img/poses/reading.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## Discord notifications

Long turns, errors and backups also land in a Discord channel, as embeds
with Frieren art per event. Opt-in: save the webhook URL to
`~/.config/frieren/discord-webhook.env` (mode 600), then `/discord on` and
`/discord test`. The URL never appears in logs or process lists.

<div class="gallery" markdown="1">

<figure>
  <img src="{{ '/assets/img/shot-discord-done.png' | relative_url }}" alt="Done notification embed" loading="lazy">
  <figcaption>Done: how long the turn took and what it was asked to do.</figcaption>
</figure>

<figure>
  <img src="{{ '/assets/img/shot-discord-error.png' | relative_url }}" alt="Error notification embed" loading="lazy">
  <figcaption>Error: what failed, with the same prompt context.</figcaption>
</figure>

<figure>
  <img src="{{ '/assets/img/shot-discord-reminder.png' | relative_url }}" alt="Reminder notification embed" loading="lazy">
  <figcaption>Reminder: violet embed with the think pose.</figcaption>
</figure>

<figure>
  <img src="{{ '/assets/img/shot-discord-backup.png' | relative_url }}" alt="Backup notification embed" loading="lazy">
  <figcaption>Backup: the new file, with the home dir shortened to `~`.</figcaption>
</figure>

<figure>
  <img src="{{ '/assets/img/shot-discord-info.png' | relative_url }}" alt="Info notification embed" loading="lazy">
  <figcaption>Plain notes use the idle pose.</figcaption>
</figure>

</div>

</section>

<section id="install" markdown="1">
<img class="deco deco-left" src="{{ '/assets/img/poses/cast.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## Summoning ritual (install)

Requirements: [Quickshell](https://quickshell.org) 0.3+, [opencode](https://opencode.ai)
v2, Hyprland, Qt 6, `sqlite3`, and a C toolchain with the `gio` headers
(on Arch: `base-devel` plus `glib2`).

```bash
curl -fsSL https://raw.githubusercontent.com/frieren-labs/frieren-desk/main/install.sh | bash
```

Then open **Frieren** from the app menu, or run `~/.local/bin/frieren`. The
opencode account is configured from the tray menu after install.

Hook it into the compositor. For DankMaterialShell add to
`~/.config/hypr/dms/binds-user.lua`:

```lua
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c frieren ipc call frieren toggle"))
```

Otherwise copy `hypr/frieren.lua` from the repo to `~/.config/hypr/` and add
`require("frieren")` at the end of the Hyprland lua config. For autostart:

```lua
hl.on("hyprland.start", function() hl.exec_cmd("qs -c frieren -n") end)
```

Verify the install:

```bash
~/.local/bin/frieren
qs -c frieren ipc call frieren ping
```

<div class="note" markdown="1">
<strong>First login is manual.</strong> Open the tray icon and choose
<strong>Settings</strong> then <strong>Model & account</strong>: paste an API key (sent over stdin to
<code>opencode auth import</code>, never written to a file) or use Terminal
login for OAuth flows. Check with <code>opencode auth list --format json</code>.
An <code>OPENCODE_API_KEY</code> in the environment also counts as connected.
</div>

</section>

<section id="controls" markdown="1">
<img class="deco" src="{{ '/assets/img/poses/reading.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## Controls and chat

| Gesture | Effect |
| --- | --- |
| Click pet | open or close the chat |
| Double-click | fresh conversation |
| Right-click pet | open the chat on the history list |
| Drag pet | move her (position is saved) |
| Drop on top bar or dock | minimize to the tray |
| `SUPER + SHIFT + R` | open the chat from anywhere |
| `Esc` or `x` | close the chat |
| `+` | new conversation |
| `■` | stop the current run |

The chat renders Markdown (headings, lists, quotes, inline code, fenced blocks,
links). The history view (`=` icon) lists past conversations with instant title
search plus full-text search over message bodies from 2 characters.

Slash commands: `/new`, `/retry`, `/export`, `/stats`, `/model provider/name`,
`/agent name`, `/sound on|off`, `/voice on|off|id`, `/volume 10-150`,
`/discord on|off|test`, `/help`.
Type `/` for suggestions, `@` for `@window` (appends the focused Hyprland
window). Drag files or screenshots into the chat to attach their paths.
`◉` next to the send button dictates from the mic.

### Remote control (IPC)

```bash
qs -c frieren ipc call frieren toggle
qs -c frieren ipc call frieren ask "how much disk is free on /"
qs -c frieren ipc call frieren fresh
qs -c frieren ipc call frieren stop
qs -c frieren ipc call frieren stats
qs -c frieren ipc call frieren backup
qs -c frieren ipc call frieren say "done, starting from scratch"
qs -c frieren ipc call frieren scale 1.15
qs -c frieren ipc call frieren sleep toggle
qs -c frieren ipc call frieren ping
qs -c frieren ipc call frieren quit
```

</section>

<section id="tray" markdown="1">
<img class="deco deco-left" src="{{ '/assets/img/poses/idle.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## Tray menu

- `Show / Hide pet`
- `Open / Close chat`
- `Settings` (window with `Pet`, `Sound & voice`, `Data`, `Model & account` tabs)
- `About` (project, author, happy Frieren, repository, MIT license)
- `Quit`

</section>

<section id="helpers" markdown="1">
<img class="deco" src="{{ '/assets/img/poses/cast.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## Artifacts (helper CLIs)

Installed by `install.sh` into `~/.local/bin`:

| Command | What it does |
| --- | --- |
| `frieren` | open the pet / toggle the chat |
| `frieren-stats [days] [--json]` | activity dashboard from `frieren.db` |
| `frieren-ask` | quick prompt via rofi, wofi, fuzzel, bemenu or dmenu |
| `frieren-shot` | screenshot (grim + slurp) straight into the chat |
| `frieren-backup [backup\|restore latest\|list]` | hot-copy `frieren.db` into backups (prunes to 10) |
| `frieren-voice [list\|download <id>\|use <id>]` | voice catalog (`en-jenny`, `es-davefx`, `es-sharvard`) |
| `frieren-weekly` | AI summary of the last 7 days via opencode |

</section>

<section id="data" markdown="1">
<img class="deco deco-left" src="{{ '/assets/img/poses/sleep.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## Memory (history and activity log)

Both live in `~/.local/state/frieren/frieren.db` (SQLite). History keeps the
last 60 conversations and up to 150 messages each; only conversations with at
least one question are stored. Every finished turn and tool call is also logged
to `turns` and `tools` tables, with a `daily` view for dashboards.

```bash
frieren-stats        # last 14 days, totals, top failures, slowest turns
frieren-stats 30     # last 30 days
frieren-stats --json # daily view as JSON
```

For a web view of the same database (turns, tools, history, reminders), see
[frieren-dashboard](https://github.com/frieren-labs/frieren-dashboard).

```bash
# success rate per day
sqlite3 ~/.local/state/frieren/frieren.db "select * from daily order by day desc limit 14;"

# slowest turns
sqlite3 ~/.local/state/frieren/frieren.db \
  "select prompt, duration_ms from turns order by duration_ms desc limit 10;"
```

Disable activity rows from Settings then `Data` then `Activity log`
(history keeps working). Raw events also append to `events.jsonl`, rotated past
about 5 MB.

</section>

<section id="config" markdown="1">
<img class="deco" src="{{ '/assets/img/poses/idle.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## Config file

`~/.config/frieren/settings.json`, created on the first change and watched
live. It wins over `state.json`, so hand-editing applies without reopening
the pet. Keys: `model`, `agent`, `wander`, `sleep`, `blink`, `log`, `sound`,
`voice`, `voiceId`, `volume`, `discord`, `scale` (0.7 to 1.4).

```json
{
  "model": "opencode-go/deepseek-v4.1-flash",
  "agent": "frieren",
  "sound": true,
  "voice": false
}
```

Change the model from the account dialog (`Change` lists `opencode models`,
current provider first) or edit `model` in the agent markdown at
`~/.config/opencode/agents/frieren.md` together with `modelName` in
`shell.qml`. It must be one your account can pay for.

</section>

<section id="safety" markdown="1">
<img class="deco deco-left" src="{{ '/assets/img/poses/sad.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## Wardings (safety)

<div class="note safe" markdown="1">
The agent carries a denylist: <code>sudo</code>, <code>doas</code>,
<code>su</code>, <code>rm -rf /</code>, <code>mkfs</code>,
<code>dd of=/dev/*</code>, <code>shutdown</code>, <code>reboot</code>,
poweroff, piped shells and secret reads (<code>~/.ssh</code>,
<code>~/.gnupg</code>, <code>~/.aws</code>, <code>.env</code>,
<code>*.pem</code>, <code>auth.json</code>). Secrets travel over stdin only,
never in argv, logs or state files.
</div>

</section>

<section id="source" markdown="1">
<img class="deco" src="{{ '/assets/img/poses/celebrate.png' | relative_url }}" alt="" aria-hidden="true" loading="lazy">

## Source and contributions

PRs welcome. Keep code and docs in English. See
[CONTRIBUTING.md](https://github.com/frieren-labs/frieren-desk/blob/main/CONTRIBUTING.md).
Full reference lives in
[`quickshell/frieren/README.md`](https://github.com/frieren-labs/frieren-desk/blob/main/quickshell/frieren/README.md),
the interactive architecture diagram in `docs/architecture.html`.

</section>

</div>
