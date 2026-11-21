#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
QS_DIR="$CONFIG/quickshell/frieren"
OC_DIR="$CONFIG/opencode/agents"
FORCE=0

[ "${1:-}" = "--force" ] && FORCE=1

command -v qs >/dev/null 2>&1 || {
  echo "error: quickshell is missing (package: quickshell, binary: qs)" >&2
  exit 1
}

command -v opencode >/dev/null 2>&1 || \
  echo "warning: opencode is not in PATH. The pet opens, but chat will not respond." >&2

command -v python3 >/dev/null 2>&1 || \
  echo "warning: python3 is missing. The tray icon will not start." >&2

python3 -c "import dbus, gi" >/dev/null 2>&1 || \
  echo "warning: install python-dbus and python-gobject to get the tray icon." >&2

mkdir -p "$QS_DIR" "$OC_DIR"
cp -R "$ROOT/quickshell/frieren/." "$QS_DIR/"

if [ -e "$OC_DIR/frieren.md" ] && [ "$FORCE" -ne 1 ]; then
  echo "warning: $OC_DIR/frieren.md already exists, not overwriting it (use --force)" >&2
else
  cp "$ROOT/opencode/agents/frieren.md" "$OC_DIR/frieren.md"
fi

cat <<'EOF'

Installed. You still need to hook it into the compositor.

DankMaterialShell: add the bind to ~/.config/hypr/dms/binds-user.lua

  hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c frieren ipc call frieren toggle"))

Hyprland with your own config: copy hypr/frieren.lua to ~/.config/hypr/ and add
require("frieren") at the end of hyprland.lua.

To start it automatically on every login, add this to the same file:

  hl.on("hyprland.start", function()
      hl.exec_cmd("qs -c frieren -n")
  end)

Try it now:

  qs -c frieren -d
  qs -c frieren ipc call frieren toggle

Before using it, check the model in opencode/agents/frieren.md and in
quickshell/frieren/shell.qml (modelName): it must be one your account can pay for.
EOF
