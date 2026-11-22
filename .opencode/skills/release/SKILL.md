---
name: release
description: |
  Cut a Frieren Desk release: date tag plus GitHub Release with notes.
  Releases are automatic on push to main via release.yml; use this flow for
  manual releases, version overrides, or when the automation needs a rerun.
  MUST USE whenever the user asks to make a release, cut a release,
  tag a new version, publish a release, do a release, release vX.X.X,
  ship a new version, prepare a release, or any similar phrasing.
argument-hint: "[version] [description]"
---

# /release — Frieren Desk release process

Repo: [jd-apprentice/frieren-desk](https://github.com/jd-apprentice/frieren-desk).
Single repo, no packages, no version files: git tags plus conventional commits
are the release record. `install.sh` pulls from `main` by default, so a tag
marks a known-good installer snapshot.

## Release model

- Default tag: `v<YYYY.MM.DD>` (for example `v2026.11.22`), with `-2`, `-3`
  when the same day repeats. Do not invent semver: nothing in the repo carries
  a version number.
- Releases are **automatic on push to `main`** (`.github/workflows/release.yml`):
  docs-only pushes (`docs/`, `.archify/`, root `*.md`) and commits tagged
  `[skip release]` are skipped.
- Release body: change list from commits since the previous tag, plus the
  install command. No binaries are attached: the installer compiles the tray
  helper locally.
- Nothing deploys anywhere. A release is a tag plus GitHub Release notes.

## Inputs

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `version` | `string` | `v<today>` | Tag override (for example a semver like `v1.4.0` for a milestone) |
| `description` | `string` | from commits | One-line summary used as release title suffix |
| `dryRun` | `boolean` | `true` | Preview tag and notes without creating anything |

## Steps

1. **Preflight**
   - `git status` clean, on `main`, `git fetch origin`, `git tag --list | sort -V | tail -5`.
   - `gh auth status` works.
   - CI on `main` is green (`gh run list --workflow=ci --limit 3`).
   - Decide the tag: default `v<today>` (plus `-2` on repeat), or the
     requested `version`.
2. **Notes**
   - Range: previous tag to `HEAD` (`git log <prev>..HEAD --oneline --no-merges`).
   - Group by conventional-commit type. One line per change, no internals.
   - Breaking changes (removed IPC, changed `settings.json` keys, DB schema
     changes in `frieren.db` tables) get their own section with an upgrade
     action, even though the tag is date-based.
3. **Create** (skip on dry run)
   ```bash
   git tag -a <tag> -m "<tag> — <short description>"
   gh release create <tag> --title "<tag>" --notes-file /tmp/release-notes.md
   git push origin <tag>
   ```
   Or rerun the automation: `gh workflow run release.yml` on `main` (it
   computes the next tag itself).
4. **Verify**
   - `gh release view <tag>` shows the notes.
   - `curl -fsSL https://github.com/jd-apprentice/frieren-desk/archive/refs/tags/<tag>.tar.gz`
     downloads a tarball.
5. **Rollback**: `gh release delete <tag> --yes && git push origin :<tag> &&
   git tag -d <tag>`. Never re-tag a deleted tag name with different bytes.

## Gotchas

- The release workflow needs `contents: write` on `GITHUB_TOKEN`; without it
  tag creation fails. That permission lives in `release.yml`, keep it.
- `fetch-depth: 0` is required: shallow clones have no tags, so the
  next-tag computation and the commit range break silently.
- Docs-only pushes do not release (paths-ignore). A docs fix that must ship
  notes needs a manual release.
- Em dash ban: use periods, commas, colons, parentheses or hyphens in notes.
  Keep code, docs and notes in English.
- Voice models under `~/.local/share/frieren/voice/` are downloaded, never
  committed. Releases never bundle them.
