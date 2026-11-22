![Frieren](assets/frieren-banner.png)

# Frieren Desk

A chibi Frieren that lives on your Hyprland desktop. Drag her around, click her
to chat with [opencode](https://opencode.ai), and ask her to read, edit or run
things on the system. She reacts to what is happening (thinking, casting,
success, error, sleep), wanders on her own, and minimizes to a real tray icon
with a settings menu.

## Install

Requires [Quickshell](https://quickshell.org) 0.3+, [opencode](https://opencode.ai)
v2, Hyprland, Qt 6, `sqlite3` (chat history and activity log), and a C toolchain
with the `gio` headers (on Arch: `base-devel` plus `glib2`).

```bash
curl -fsSL https://raw.githubusercontent.com/jd-apprentice/frieren-desk/main/install.sh | bash
```

Then open **Frieren** from the app menu, or run `~/.local/bin/frieren`. The
opencode account is configured from the tray menu after install.

- Click the pet: open or close the chat.
- Chat replies render Markdown, text is selectable, and code blocks and commands
- Click the pet: open or close the chat. Double-click: fresh conversation.
  Right-click: history. Drag files into the chat to attach `@paths`.
- Header `⛁` exports the open conversation as Markdown; `%` opens the
  activity panel with the last-14-day table; `◉` dictates from the mic.
  Inside the box: `/new`, `/retry`, `/export`, `/stats`, `/model`, `/agent`,
  `/sound`, `/voice`, `/help`, `@window` for Hyprland window context.
- Sounds, `notify-send` on long turns, spoken replies, quick-ask (`frieren-ask`),
  screenshot-to-chat (`frieren-shot`), backups and `frieren-weekly`.
- Config: `~/.config/frieren/settings.json` pins `model`, `agent`, toggles and scale (live).
- Drag her to the top bar or the bottom dock: minimize to the tray.
- Click the tray icon: show/hide, chat actions, animation settings and quit.
- Tray → **About**: project, author, repository and MIT license.
- State and settings: `~/.local/state/frieren/state.json`.
- History and local activity log share `${XDG_STATE_HOME:-~/.local/state}/frieren/frieren.db`
  (SQLite). The raw event stream is also kept in `events.jsonl` (rotated past ~5 MB).
  `frieren-stats` prints the dashboard (`--json` for scripts).

## What it looks like

![Frieren poses with the chat panel open](assets/poses-preview.png)

| Pose | When it shows | Chat line |
| --- | --- | --- |
| `idle` | waiting, or wandering around | `ask me something` |
| `think` | opencode is reasoning | `thinking…` |
| `cast` | a tool is running | `casting a spell…` |
| `happy` | a task finished, or she wakes up | `done` |
| `sad` | an error came back | `oops…` |
| `sleep` | idle for a while with sleep enabled | `zzz…` |

The image shows the real sprites from `quickshell/frieren/assets/poses/`, so it
matches what you get after install.

## Docs

| Topic | Where |
| --- | --- |
| Config, tray menu and animations | `quickshell/frieren/README.md` |
| Chat history and activity log | `quickshell/frieren/README.md` (History and activity log) |
| OpenCode account setup | tray menu, `quickshell/frieren/components/AuthDialog.qml`, `shell.qml` |
| Persona, permissions and command denylist | `opencode/agents/frieren.md` |
| Source sprite sheet (art reference) | `assets/frieren-sheet.png` |
| Tray icon pipeline (development) | `tools/make_icon.sh` |
| Hyprland bind and autostart | `hypr/frieren.lua` |
| Installer and app menu launcher | `install.sh`, `tools/frieren-launch.sh` |

## Contributing

PRs welcome. Keep the code and docs in English.

## License

MIT. See [LICENSE](LICENSE). Frieren is a fan-art sprite; the character belongs
to Kanehito Yamada and Tsukasa Abe.
