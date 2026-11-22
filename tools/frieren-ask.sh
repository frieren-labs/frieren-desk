#!/usr/bin/env bash
# frieren-ask: prompt for a one-line question and send it to Frieren via qs IPC.
# Usage: frieren-ask.sh
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/frieren"
DB="$STATE/frieren.db"

PICKER=""
for c in rofi wofi fuzzel bemenu dmenu; do
  if command -v "$c" >/dev/null 2>&1; then
    PICKER="$c"
    break
  fi
done

if [ -z "$PICKER" ]; then
  echo "error: no picker found (tried rofi, wofi, fuzzel, bemenu, dmenu)" >&2
  exit 1
fi

# CONFIG/DATA/DB are defined for convention; only PICKER and qs are used here.

text=""
case "$PICKER" in
  rofi) text="$(rofi -dmenu -p "Frieren" || true)" ;;
  wofi) text="$(wofi --dmenu -p "Frieren" || true)" ;;
  fuzzel) text="$(fuzzel --dmenu --prompt "Frieren: " || true)" ;;
  bemenu) text="$(bemenu -p "Frieren" || true)" ;;
  dmenu) text="$(dmenu -p "Frieren" || true)" ;;
esac

if [ -z "${text:-}" ]; then
  exit 0
fi

command -v qs >/dev/null 2>&1 || { echo "error: qs not found in PATH" >&2; exit 1; }

qs -c frieren ipc call frieren ask "$text"
