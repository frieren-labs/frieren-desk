# Quickshell qmltypes for CI lint

`qmllint` in CI runs on Ubuntu without Quickshell installed, so the
`Quickshell` and `Quickshell.Io` imports cannot resolve there. These files
give the linter the module type information so property checks still run
instead of degrading to "not found" noise.

- `quickshell-core.qmltypes`, `quickshell-io.qmltypes`: verbatim copies from an
  installed Quickshell, minus `isTypeOpaque` lines (that key postdates the Qt 6.4
  qmllint used in CI and makes it reject the whole file). Source: Arch package
  `quickshell 0.3.2-1.1`. Regenerate by copying the same two files and re-applying
  the strip, keeping this note in sync with the version.
- `quickshell-fileview.qmltypes`: hand-written. The real `FileView` is defined in
  `FileView.qml` upstream, so `qmltyperegistrar` output has no entry for it. Covers
  only the used API (`path`, `printErrors`, `watchChanges`, `text()`,
  `onLoaded`/`onLoadFailed`); extend it if new FileView members are used.
- Passed to qmllint with `-i` (see `.github/workflows/ci.yml`). The remaining
  `[import]` warnings (unresolvable module imports) are filtered as environmental.
