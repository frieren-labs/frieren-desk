#!/usr/bin/env bash
# frieren-backup: hot-copy backup / restore / list for frieren.db.
# Usage: frieren-backup.sh [backup|restore <file>|restore latest|list]
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/frieren"
DB="$STATE/frieren.db"
BACKUPS="$DATA/frieren/backups"

# CONFIG is defined for convention; DB/BACKUPS carry the logic.

CMD="${1:-backup}"
ARG="${2:-}"

command -v sqlite3 >/dev/null 2>&1 || { echo "error: sqlite3 not found" >&2; exit 1; }

do_backup() {
  [ -f "$DB" ] || { echo "error: no database at $DB" >&2; exit 1; }
  mkdir -p "$BACKUPS"
  TS="$(date +%Y%m%d-%H%M%S)"
  DST="$BACKUPS/frieren-$TS.db"
  sqlite3 "$DB" ".backup main '$DST'"
  # prune: keep newest 10
  count="$(ls -1 "$BACKUPS"/frieren-*.db 2>/dev/null | wc -l)"
  if [ "$count" -gt 10 ]; then
    ls -1t "$BACKUPS"/frieren-*.db | tail -n +11 | xargs -r rm -f --
  fi
  echo "$DST"
}

do_list() {
  if ! ls "$BACKUPS"/frieren-*.db >/dev/null 2>&1; then
    echo "no backups yet"
    return 0
  fi
  ls -1t "$BACKUPS"/frieren-*.db | xargs -n1 basename --
}

do_restore() {
  src="$1"
  if [ "$src" = "latest" ]; then
    ls "$BACKUPS"/frieren-*.db >/dev/null 2>&1 || { echo "error: no backups yet" >&2; exit 1; }
    src="$(ls -1t "$BACKUPS"/frieren-*.db | head -n 1)"
  fi
  [ -f "$src" ] || { echo "error: backup not found: $src" >&2; exit 1; }
  mkdir -p "$(dirname "$DB")"
  if [ -f "$DB" ]; then
    TS="$(date +%Y%m%d-%H%M%S)"
    cp -f "$DB" "$DB.pre-restore-$TS"
    echo "saved current DB as $DB.pre-restore-$TS"
  fi
  cp -f "$src" "$DB"
  echo "restored $src to $DB"
}

case "$CMD" in
  backup) do_backup ;;
  list) do_list ;;
  restore)
    [ -n "$ARG" ] || { echo "usage: frieren-backup.sh [backup|restore <file>|restore latest|list]" >&2; exit 1; }
    do_restore "$ARG"
    ;;
  *) echo "usage: frieren-backup.sh [backup|restore <file>|restore latest|list]" >&2; exit 1 ;;
esac
