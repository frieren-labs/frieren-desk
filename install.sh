#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
QS_DIR="$CONFIG/quickshell/frieren"
OC_DIR="$CONFIG/opencode/agents"
FORCE=0

[ "${1:-}" = "--force" ] && FORCE=1

command -v qs >/dev/null 2>&1 || {
  echo "error: falta quickshell (paquete: quickshell, binario: qs)" >&2
  exit 1
}

command -v opencode >/dev/null 2>&1 || \
  echo "aviso: opencode no está en PATH. La mascota abre, pero el chat no va a responder." >&2

mkdir -p "$QS_DIR" "$OC_DIR"
cp -R "$ROOT/quickshell/frieren/." "$QS_DIR/"

if [ -e "$OC_DIR/frieren.md" ] && [ "$FORCE" -ne 1 ]; then
  echo "aviso: ya existe $OC_DIR/frieren.md, no lo piso (usá --force)" >&2
else
  cp "$ROOT/opencode/agents/frieren.md" "$OC_DIR/frieren.md"
fi

cat <<'EOF'

Instalado. Falta engancharlo al compositor.

DankMaterialShell (tu caso): agregá el bind a ~/.config/hypr/dms/binds-user.lua

  hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c frieren ipc call frieren toggle"))

Hyprland con config propia: copiá hypr/frieren.lua a ~/.config/hypr/ y agregá
require("frieren") al final de hyprland.lua.

Para que arranque solo en cada login, sumá al mismo archivo:

  hl.on("hyprland.start", function()
      hl.exec_cmd("qs -c frieren -n")
  end)

Probarlo ahora:

  qs -c frieren -d
  qs -c frieren ipc call frieren toggle

Antes de usarlo, revisá el modelo en opencode/agents/frieren.md y en
quickshell/frieren/shell.qml (modelName): tiene que ser uno que tu cuenta pueda pagar.
EOF
