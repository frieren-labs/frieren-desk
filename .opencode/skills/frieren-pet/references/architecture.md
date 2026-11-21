# Architecture

## What this project is

A Quickshell configuration named `frieren` that draws a chibi Frieren on a
Hyprland overlay, opens a chat panel next to her, and sends each message to
`opencode run` using a dedicated agent. A small C helper publishes a real tray
icon with a DBusMenu.

## File map

| Path | Role |
| --- | --- |
| `quickshell/frieren/shell.qml` | `ShellRoot`: windows, theme, state, chat model, opencode process, tray helper process, IPC |
| `quickshell/frieren/components/PetSprite.qml` | Sprite, poses, timers, animations, drag, click |
| `quickshell/frieren/components/ChatPanel.qml` | Chat frame, header, list and input |
| `quickshell/frieren/components/MessageBubble.qml` | Message and tool log rendering |
| `quickshell/frieren/tray.c` | Native StatusNotifierItem and `com.canonical.dbusmenu` helper (compiled to `frieren-tray`) |
| `quickshell/frieren/components/AuthDialog.qml` | OpenCode account card (status, key, terminal login) |
| `quickshell/frieren/assets/poses/` | Six 228x256 PNG poses plus `poses.json` metadata |
| `assets/frieren-sheet.png` | Source sprite sheet, kept as art reference |
| `assets/poses-preview.png` | README showcase image (checked in) |
| `quickshell/frieren/assets/frieren-icon*.png` | Tray icon and chat avatar |
| `opencode/agents/frieren.md` | Persona, model and permission denylist |
| `tools/make_icon.sh` | Builds the tray icon and raw ARGB buffers |
| `hypr/frieren.lua` | Keybind and autostart |
| `install.sh` | Copies the shell and agent into `~/.config` |

The installed copy lives in `~/.config/quickshell/frieren/`. Editing the repo
alone does not affect the running pet until `install.sh` copies the files or you
edit the installed copy when testing.

## Runtime data flow

```text
click / keybind / tray / IPC
          |
          v
     ShellRoot.send()
          |
          v
 opencode run --format json --session <id>
          |
          | stdout: one JSON event per line
          v
     handleLine()
      |        |
      v        v
  chat list  busy / toolActive / hasError
      |        |
      v        v
 ChatPanel  PetSprite.mood and animations
```

State changes go to `~/.local/state/frieren/state.json` through
`saveState()`. `tray.c` reads that file and listens to IPC calls.

## Windows

### Pet window

`petWin` is a `PanelWindow` anchored to all edges of one screen:

- Layer: `WlrLayer.Overlay`.
- `exclusionMode: ExclusionMode.Ignore` so it does not reserve space.
- `WlrLayershell.keyboardFocus: None` so it never steals the keyboard.
- `mask: Region { item: hitArea }` limits input to the pet rectangle.
- `hitArea` follows `pet.x` and `pet.y`; the pet itself owns its position.
- The window size comes from `petWin.screen`.

Do not replace the mask with a full-window `MouseArea`. The rest of the desktop
must stay clickable.

### Chat window

`chatWin` is a separate `PanelWindow`:

- Visible only when `chatOpen && !minimized`.
- `WlrLayershell.keyboardFocus: OnDemand`, `focusable: true`.
- Fixed width 430, height between 320 and 560 depending on the screen.
- Placed to the left or right of the pet by `onLeft`, `chatLeft()` and `chatTop()`.
- Clamped to the screen with a 14 px gap.

If keyboard focus does not arrive when the chat opens, the documented fallback
is `WlrKeyboardFocus.Exclusive`, but it blocks global keys while open.

### Account dialog

`authWin` is a third fullscreen `PanelWindow`:

- Visible only when `authOpen`; `mask: Region { item: authDialog }` keeps the
  rest of the desktop clickable.
- Centered `AuthDialog` card, `WlrLayershell.keyboardFocus: OnDemand`.
- Shows the status from `opencode auth list` and offers key import, terminal
  login and a manual re-check.
- Polls the status every 4 seconds while open (except while saving) so a login
  finished in a terminal is picked up.
- It is declared after `chatWin`, so it renders above the chat.

## Theme

`shell.qml` defines a fallback `theme` object, then overrides it from DMS files:

- `~/.cache/dms/dms-colors.json` (mode-aware colors).
- `~/.cache/dms/dms-typography.json` (font families).

Both are watched with `FileView`. Components receive the theme object as a
property. `PetSprite` still uses the literal family `Google Sans Flex` for the
sleeping `z` letters and the hint; change that to the theme font when touching
the component.

## Process topology

```text
qs -c frieren
├── opencode run ...        (one process per message)
├── opencode auth ...       (short-lived status, import, switch, logout)
├── sh -c <terminal> ...    (terminal login, only when requested)
└── frieren-tray ...        (long-lived native helper, child of qs)
```

- The opencode process runs with `HOME` as the working directory and a PATH that
  starts with `~/.opencode/bin`.
- Its stdin is closed with `< /dev/null`. Without that, opencode waits for EOF.
- The tray helper owns the bus name `org.kde.StatusNotifierItem-frieren` and is
  a child of `qs`. It takes a parent death signal, so it exits with the shell,
  and it watches `state.json` with a Gio file monitor.
