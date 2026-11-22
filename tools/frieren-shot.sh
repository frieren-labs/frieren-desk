#!/usr/bin/env bash
# frieren-shot: capture a screenshot and send it to Frieren chat.
# Usage: frieren-shot.sh
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/frieren"
DB="$STATE/frieren.db"

# CONFIG/DB are defined for convention; only DATA (shots dir) is used here.

command -v grim >/dev/null 2>&1 || {
  echo "error: grim not found; install grim (and slurp for region select)" >&2
  exit 1
}

SHOTS="$DATA/frieren/shots"
mkdir -p "$SHOTS"
TS="$(date +%Y%m%d-%H%M%S)"
FILE="$SHOTS/shot-$TS.png"

if command -v slurp >/dev/null 2>&1; then
  GEO="$(slurp)"
  if [ -z "${GEO:-}" ]; then
    exit 0
  fi
  grim -g "$GEO" "$FILE"
else
  echo "warning: slurp not found, capturing full screen" >&2
  grim "$FILE"
fi

if ! command -v qs >/dev/null 2>&1; then
  echo "error: qs not found in PATH; screenshot saved at $FILE" >&2
  echo "$FILE"
  exit 1
fi

qs -c frieren ipc call frieren ask "@$FILE describe this screenshot briefly"
