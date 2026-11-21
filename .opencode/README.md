# Project skills

Skills installed for this repository only. OpenCode discovers them from
`.opencode/skills/` when it runs inside this project, without affecting other
projects. Each directory is one skill and keeps its own license file.

| Skill | Source | Why it is here |
| --- | --- | --- |
| `qt-qml` | [TheQtCompanyRnD/agent-skills](https://github.com/TheQtCompanyRnD/agent-skills) | QML best practices for writing and refactoring the pet, chat and tray UI |
| `qt-qml-review` | same | Reviews QML changes before committing (bindings, layouts, delegates, performance) |
| `qt-qml-docs` | same | Generates reference docs from the QML sources |
| `qt-qml-profiler` | same | Profiles the shell when the pet or chat feels slow |
| `qt-qml-test` | same | Writes Qt Quick Test cases for components such as `MessageBubble` |
| `qt-ui-design` | same | Layout and UX audits for the pet and chat panel |
| `dms-plugin-dev` | [duxlabs-dev/dux-shell](https://github.com/duxlabs-dev/dux-shell) | DMS plugin API, theme integration, popouts and persistence, for a possible native DMS widget |
| `frieren-pet` | This repository | Project invariants: state schema, mood machine, timers, poses, tray and IPC contracts, backend events, verification recipes |

## Provenance

- Qt skills: `TheQtCompanyRnD/agent-skills` at commit `745a805`, directory `skills/`.
  License per skill: `LicenseRef-Qt-Commercial OR BSD-3-Clause` (see each
  `LICENSE.txt`).
- DMS skill: `duxlabs-dev/dux-shell` at commit `745a805`, directory
  `.agents/skills/dms-plugin-dev/`. License: MIT (see `LICENSE`).
- `frieren-pet` is original content for this repository and follows the
  repository MIT license.

## Notes

- These are third-party instructions. Review a `SKILL.md` before relying on it.
- The Qt skills are the QML and UI subset. C++, CMake, Figma and Canvas2D
  skills were intentionally left out because this project does not use them.
- To update, copy the new skill directory over the existing one and refresh
  this table.
