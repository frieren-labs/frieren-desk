# AGENTS.md — Frieren Desk

Quickshell desktop pet for Hyprland. QML shell (`quickshell/frieren/`), C tray helper
(`tray.c`), activity hook, CLI tools (`tools/`), opencode agent (`opencode/agents/frieren.md`).

## Source of truth for pet work

Read `.opencode/skills/frieren-pet/SKILL.md` first. It has the change map (which files
per task), hard rules, recipes (tray setting, IPC method, pose, chat, activity
event) and the known-pitfalls list. `references/verification.md` has the manual test
matrix; `references/state-tray-ipc.md` covers tray menu IDs and IPC.

## Repo vs installed copy

The running pet uses `~/.config/quickshell/frieren/`, not this repo. After editing,
run `./install.sh` and restart the pet (`.opencode/skills/frieren-pet/scripts/restart.sh`),
then verify with `.opencode/skills/frieren-pet/scripts/health.sh`. Never run two `qs -c frieren`
instances: they share one state file and fight over the pet position.

## Verify before finishing

```bash
bash -n install.sh tools/*.sh quickshell/frieren/hooks/*.sh quickshell/frieren/tools/*.sh
qmllint quickshell/frieren/components/*.qml
cc -O2 -Wall -o /tmp/frieren-tray-test quickshell/frieren/tray.c $(pkg-config --cflags --libs gio-2.0)
```

`qmllint shell.qml` exits 255 on missing Quickshell qmltypes (pre-existing baseline,
informational only in CI). CI (`pull_request` only) additionally filters `[import]` and
`[unqualified]` warnings; fail on any other category. `tools/qmltypes/` holds vendored
Quickshell type descriptions for CI (`-i` flags); if CI reports unknown qmltypes keys,
strip the new key and note the Qt version in `tools/qmltypes/README.md`.

## Branches, commits, PRs

- Branches: `feature/description`, `fix/description`, `docs/description`. Conventional Commits.
- CI runs on pull requests only. Work on a branch, open a PR, merge after green.
  Dependabot merges to main happen; rebase before pushing.
- Pushing to `main` triggers an automatic date-tagged GitHub release
  (`.github/workflows/release.yml`, skipped for docs-only changes and `[skip release]`
  commits). See `.opencode/skills/release/SKILL.md` for manual releases.
- English everywhere: code, docs, commits. No em dashes (U+2014).

## Hard-earned QML rules

- Repeating `Process` writers (history, stats, hook, export, say, auth): set
  `stdinEnabled = true` again in `onStarted` before `write()`, then `false` to
  send EOF. Without the re-enable, the first run works and every later run hangs
  forever on open stdin. (`StdioCollector.text` does not accumulate across runs.)
- `shell.qml` `loadState()` must stay pure assignments: an exception inside is
  swallowed by `catch`, silently skipping the rest of the restore.
- `settings.json` wins over `state.json`. Gate state loads with `hasSetting(key)`
  so either file loading first converges to settings values.
- `saveState()` writes a `.tmp` file and moves it; the tray watches it by mtime.
- History is keyed by `activeConvId`. Never assign `sessionId` directly; always go
  through `adoptSessionId()` or conversations duplicate. SQL and JSON payloads go over
  `sqlite3` stdin, never argv (argv length limits).
- QML `id`s used from `root.*` functions must exist at file scope (`pet`,
  `chatPanel`, `historyLoader`); a renamed id fails silently at runtime, not at lint.

## Pet UI invariants

- Never remove the pet window `mask: Region { item: hitArea }`; the desktop stops
  receiving clicks without it.
- Selectable text needs read-only `TextEdit` with `selectByMouse` (`Text` has no
  mouse selection in Qt 6). Copy via `Quickshell.clipboardText`, never `wl-copy`.
- Chat scroll lock lives in `list.follow`. Never add unconditional
  `positionViewAtEnd` on count/content-height change; it drags the view while the
  user scrolls up.
- Tray `tray.c` stays on GIO/GDBus only. DBusMenu `toggle-type` is `checkmark` or
  `radio` (never `check`). Menu IDs are stable; voice radios use dynamic IDs 30-49.
- The opencode key travels over stdin to `opencode auth import` only. Never in argv,
  `ps`, `state.json` or logs. Treat the agent denylist as guardrail, not sandbox.
- Subagent-spawned work and background shells must not edit the same QML file
  concurrently; `shell.qml` edits are strictly sequential.

## Paths (XDG-aware, never hardcode `~/.local`)

- State DB: `${XDG_STATE_HOME:-~/.local/state}/frieren/frieren.db`
- Settings: `${XDG_CONFIG_HOME:-~/.config}/frieren/settings.json`
- Voices: `${XDG_DATA_HOME:-~/.local/share}/frieren/voice/voices/`
- User CLIs install to `${XDG_BIN_HOME:-~/.local/bin}/frieren-*`
