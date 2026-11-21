![Frieren](assets/frieren-banner.png)

# Frieren Desk

A chibi Frieren that lives on your Hyprland desktop. Drag her around, click her
to chat with [opencode](https://opencode.ai), and ask her to read, edit or run
things on the system. She reacts to what is happening (thinking, casting,
success, error, sleep), wanders on her own, and minimizes to a real tray icon
with a settings menu.

## Quick Start

Requires: [Quickshell](https://quickshell.org) 0.3+, [opencode](https://opencode.ai)
v2 with an authenticated provider, Hyprland, Qt 6, and `python3` with
`python-dbus` and `python-gobject` for the tray icon.

```bash
git clone https://github.com/jd-apprentice/frieren-desk.git
cd frieren-desk
./install.sh
qs -c frieren -d
```

Add the keybind and autostart from `hypr/frieren.lua`, or bind:

```lua
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c frieren ipc call frieren toggle"))
```

- Click the pet: open or close the chat.
- Drag her to the top bar or the bottom dock: minimize to the tray.
- Click the tray icon: show/hide, chat actions, animation settings and quit.
- State and settings: `~/.local/state/frieren/state.json`.

## Docs

| Topic | Where |
| --- | --- |
| Config, tray menu and animations | `quickshell/frieren/README.md` |
| Persona and permissions | `opencode/agents/frieren.md` |
| Sprite sheet and icon pipeline | `assets/frieren-sheet.png`, `tools/slice_spritesheet.py`, `tools/make_icon.sh` |
| Hyprland bind and autostart | `hypr/frieren.lua` |
| Installer | `install.sh` |

## Security

The pet runs real commands. The denylist lives in the opencode agent
(`opencode/agents/frieren.md`): no `sudo`, disk formatting, shutdown, remote
pipes or secret reads. It is a denylist, not a sandbox, so review the agent
before using it on a machine you care about.

## Contributing

PRs welcome. Keep the code and docs in English.

## License

MIT. See [LICENSE](LICENSE). Frieren is a fan-art sprite; the character belongs
to Kanehito Yamada and Tsukasa Abe.
