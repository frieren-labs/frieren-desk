---
name: Frieren Pet
description: Work on the Frieren desktop pet in this repository. Use when changing the pet sprite, poses, animations, chat panel, opencode backend, tray menu, IPC, state.json, theme integration, or the install scripts under quickshell/frieren, tools or hypr.
---

# Frieren Pet

A chibi Frieren desktop pet for Hyprland built on Quickshell. It talks to
opencode through the `frieren` agent, runs system commands, animates six poses,
and exposes a StatusNotifierItem tray menu written in Python.

This skill is project-local. It encodes the invariants that the generic QML
skills cannot know.

## Read first

1. `references/architecture.md` for the file map, windows and data flow.
2. `references/poses-and-animation.md` before touching `PetSprite.qml`, poses or timers.
3. `references/state-tray-ipc.md` before changing state, `tray.py` or IPC.
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
| Chat UI | `components/ChatPanel.qml`, `components/MessageBubble.qml` |
| Backend, events, sessions | `shell.qml` (`send`, `handleLine`, `upsertTool`, `Process agent`) |
| OpenCode account | `shell.qml` (auth properties and processes), `auth.py`, `components/AuthDialog.qml`, `tray.py` |
| State or settings | `shell.qml` (`loadState`, `saveState`, `statePath`), `tray.py` |
| Tray menu | `tray.py`, `.opencode/skills/frieren-pet/references/state-tray-ipc.md` |
| IPC | `shell.qml` (`IpcHandler`), `quickshell/frieren/README.md` |
| Theme | `shell.qml` (`theme`, `applyDmsColors`, `applyDmsType`) |
| New pose art | `assets/frieren-sheet.png`, `tools/slice_spritesheet.py`, `README.md` |
| Install or launch | `install.sh`, `hypr/frieren.lua` |

## Recipes

### Add a tray setting

1. Add the property and default in `shell.qml`.
2. Load and save it in `loadState` and `saveState`.
3. Add an entry and a stable ID in `tray.py`, using `toggle_type="checkmark"`
   for booleans and `toggle_type="radio"` for exclusive choices.
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

1. Put the new cell in `assets/frieren-sheet.png` or slice it manually to the
   228x256 canvas.
2. Follow `references/poses-and-animation.md` for the `poses.json` schema.
3. Update the `mood` mapping in `PetSprite.qml` and the pose table in `README.md`.
4. Regenerate `assets/poses-preview.png` with `tools/make_poses_preview.py`.
5. Verify the eye rectangles and the staff glow point on screen.

### Change the chat

- `MessageBubble.qml` renders four roles: `user`, `assistant`, `tool` and `system`.
- Keep `Text.PlainText` only if Markdown rendering is intentionally out of scope.
- The input is a single-line `TextInput`. Multi-line support needs a new design.
- Do not block the whole panel while `busy`; only the input is disabled.

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
- `auth.py` reads the key from stdin and never writes it to argv or to its
  output. Keep it that way when changing the login flow.
