![Frieren Desk cover](assets/frieren-cover.png)

# Frieren Desk

A chibi Frieren that lives on your Hyprland desktop. Drag her around, click her
to chat with [opencode](https://opencode.ai), and ask her to read, edit or run
things on the system. She reacts to what is happening (thinking, casting,
success, error, sleep), wanders on her own, and minimizes to a real tray icon
with a settings menu.

## Install

### For humans

Requires [Quickshell](https://quickshell.org) 0.3+, [opencode](https://opencode.ai)
v2, Hyprland, Qt 6, `sqlite3` (chat history and activity log), and a C toolchain
with the `gio` headers (on Arch: `base-devel` plus `glib2`).

```bash
curl -fsSL https://raw.githubusercontent.com/jd-apprentice/frieren-desk/main/install.sh | bash
```

Then open **Frieren** from the app menu, or run `~/.local/bin/frieren`. The
opencode account is configured from the tray menu after install.

### For agents

Paste this prompt to an agent with shell access on the target machine:

```text
Install Frieren Desk on this Hyprland machine.
Repo: https://github.com/jd-apprentice/frieren-desk

1. Check prerequisites and report versions. Fail fast if missing:
   qs --version (needs Quickshell 0.3+), opencode --version (needs v2),
   hyprctl version, sqlite3 --version, cc --version,
   pkg-config --modversion gio-2.0. On Arch the packages are:
   quickshell, opencode, sqlite, gcc (or base-devel), pkgconf, glib2.
   If opencode is missing, warn that the pet will open but chat will not respond.

2. Run the installer (add --force only to overwrite
   ~/.config/opencode/agents/frieren.md):
   curl -fsSL https://raw.githubusercontent.com/jd-apprentice/frieren-desk/main/install.sh | bash

3. Hook it into the compositor:
   - If ~/.config/hypr/dms/binds-user.lua exists (DankMaterialShell), add:
     hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c frieren ipc call frieren toggle"))
     and skip the require below.
   - Otherwise copy hypr/frieren.lua from the repo to ~/.config/hypr/frieren.lua
     and add require("frieren") at the end of the Hyprland lua config.
   - For autostart on every login, add:
     hl.on("hyprland.start", function() hl.exec_cmd("qs -c frieren -n") end)

4. Launch and verify:
   ~/.local/bin/frieren
   qs -c frieren ipc call frieren ping
   The ping must answer. If ~/.local/bin is not in PATH, use the absolute path
   or the app menu entry.

5. Account setup is manual: tell the user to open the tray icon and choose
   "Setup account" (API key via opencode auth import, or Terminal login for
   OAuth flows). Verify with: opencode auth list --format json.
   An OPENCODE_API_KEY in the environment also counts as connected.

6. Model check: the model in ~/.config/opencode/agents/frieren.md and
   modelName in ~/.config/quickshell/frieren/shell.qml must be one the
   account can pay for. Default is opencode-go/deepseek-v4.1-flash.

Do not store API keys in files, argv, or logs. The key travels over stdin
to opencode auth import only.
```

## What it looks like

![Frieren poses with the chat panel open](assets/poses-preview.png)

| Pose | When it shows | Chat line |
| --- | --- | --- |
| `idle` | waiting, or wandering around | `ask me something` |
| `think` | opencode is reasoning | `thinking…` |
| `cast` | a tool is running | `casting a spell…` |
| `reading` | a read-like tool is running | `reading…` |
| `happy` | a task finished, or she wakes up | `done` |
| `celebrate` | third clean turn in a row | `amazing!` |
| `sad` | an error came back | `oops…` |
| `sleep` | idle for a while with sleep enabled | `zzz…` |

### In action (real screenshots)

| | |
| --- | --- |
| ![Pet on the desktop](assets/showcase/shot-pet.png) | ![Chat with markdown and copy buttons](assets/showcase/shot-chat.png) |
| On the desktop: click to chat, double-click for a fresh conversation, right-click for history. | Markdown replies, selectable text, copy buttons, slash-command completion. |
| ![Activity panel](assets/showcase/shot-stats.png) | ![Account dialog](assets/showcase/shot-auth.png) |
| Activity panel: turns, success rate and average time per day. | Account dialog: API key or terminal login, plus the model picker. |
| ![About dialog](assets/showcase/shot-about.png) | |
| About dialog: project, author, repository and license. | |

## Docs

| Topic | Where |
| --- | --- |
| Config, tray menu and animations | `quickshell/frieren/README.md` |
| Chat history and activity log | `quickshell/frieren/README.md` (History and activity log) |
| Architecture diagram (interactive) | `docs/architecture.html` |
| Project overview page (with sprites) | `docs/overview.html` |
| OpenCode account setup | tray menu, `quickshell/frieren/components/AuthDialog.qml`, `shell.qml` |
| Persona, permissions and command denylist | `opencode/agents/frieren.md` |
| Source sprite sheet (art reference) | `assets/frieren-sheet.png` |
| Sprite prompt for new poses | `assets/SPRITE_PROMPT.md` |
| Tray icon pipeline (development) | `tools/make_icon.sh` |
| Poses preview image (development) | `tools/make_preview.sh` (needs ImageMagick + DejaVu) |
| Hyprland bind and autostart | `hypr/frieren.lua` |
| Installer and app menu launcher | `install.sh`, `tools/frieren-launch.sh` |

## Contributing

PRs welcome. Keep the code and docs in English. See [CONTRIBUTING.md](CONTRIBUTING.md)
and the issue/PR templates in `.github/`.

## License

MIT. See [LICENSE](LICENSE). Frieren is a fan-art sprite; the character belongs
to Kanehito Yamada and Tsukasa Abe.
