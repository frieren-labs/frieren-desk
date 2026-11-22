# Quickshell qmltypes for CI lint

`qmllint` in CI runs on Ubuntu without Quickshell installed, so the
`Quickshell` and `Quickshell.Io` imports cannot resolve there. These two files
give the linter the module type information so property checks still run
instead of degrading to "not found" noise.

- Source: Arch package `quickshell 0.3.2-1.1`
  (`/usr/lib/qt6/qml/Quickshell/quickshell-core.qmltypes` and
  `Io/quickshell-io.qmltypes`).
- Regenerate with: copy the same two files from an installed Quickshell and
  keep this note in sync with its version. Then delete any `isTypeOpaque`
  lines: that key postdates the Qt 6.4 qmllint used in CI and makes it
  reject the whole file.
- Passed to qmllint with `-i` (see `.github/workflows/ci.yml`). The remaining
  `[import]` warnings (unresolvable module imports) are filtered as environmental.
