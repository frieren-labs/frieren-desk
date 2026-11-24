#!/usr/bin/env bash
# Regression tests for reminders (follow-up to #28).
# - The "today" bound must be local midnight computed with `date`. A bound
#   built with SQLite date modifiers reads wall-clock as UTC and silently
#   drops the local evening out of "que tengo hoy".
# - Firing a reminder marks done and leaves an audit row in reminder_events.
# - The agent doc keeps the date-based bound and the read-back rule.
# Usage: run from the repo root. Needs sqlite3 and GNU date. TZ is pinned.
set -euo pipefail

TZ=America/Argentina/Buenos_Aires
export TZ
command -v sqlite3 >/dev/null 2>&1 || { echo "skip: sqlite3 not found"; exit 0; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="$(mktemp)"
trap 'rm -f "$DB"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "ok: $*"; }

# Minimal equivalent of reminderSchema in quickshell/frieren/shell.qml.
# due_at is nullable: NULL rows are backlog (listed, never fired).
sqlite3 "$DB" <<'SQL'
CREATE TABLE reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  due_at INTEGER,
  recurrence TEXT NOT NULL DEFAULT 'once',
  done INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
);
CREATE TABLE reminder_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  reminder_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
);
SQL

EVENING="$(date -d 'today 22:30' +%s)"
TOMORROW="$(date -d 'tomorrow 10:00' +%s)"
YESTERDAY="$(date -d 'yesterday 09:00' +%s)"
sqlite3 "$DB" "INSERT INTO reminders (title, due_at) VALUES ('evening item', $EVENING), ('tomorrow item', $TOMORROW), ('overdue item', $YESTERDAY), ('backlog item', NULL);"

# Sanity: date-based seeds land where intended (SQLite displays them back).
[ "$(sqlite3 "$DB" "SELECT datetime($EVENING,'unixepoch','localtime');")" = "$(date -d 'today 22:30' +'%Y-%m-%d %H:%M:00')" ] || fail "seed round-trip broken"
pass "date-based seeds round-trip through SQLite"

# The old modifier-built bound (UTC midnight) drops the local evening.
OLD_BOUND="$(sqlite3 "$DB" "SELECT strftime('%s','now','+1 day','start of day');")"
old_count="$(sqlite3 "$DB" "SELECT count(*) FROM reminders WHERE done = 0 AND due_at < $OLD_BOUND;")"
[ "$old_count" = "1" ] || fail "old UTC bound should match 1 row (overdue only), got $old_count"
pass "old UTC bound reproduces the evening drop"

# The documented bound: local midnight via date.
END="$(date -d 'tomorrow 00:00' +%s)"
new_rows="$(sqlite3 "$DB" "SELECT title FROM reminders WHERE done = 0 AND due_at < $END ORDER BY due_at;")"
echo "$new_rows" | grep -q "evening item" || fail "local bound misses the evening item"
echo "$new_rows" | grep -q "tomorrow item" && fail "local bound leaks tomorrow into today"
echo "$new_rows" | grep -q "overdue item" || fail "local bound misses the overdue item"
pass "date-based today bound keeps the evening, excludes tomorrow"

# Dateless rows: excluded from the today bound and the fire query, visible
# to the backlog query and last in /tasks order.
echo "$new_rows" | grep -q "backlog item" && fail "local bound leaks backlog into today"
due_rows="$(sqlite3 "$DB" "SELECT title FROM reminders WHERE done = 0 AND due_at IS NOT NULL AND due_at <= $(date +%s) ORDER BY due_at;")"
echo "$due_rows" | grep -q "backlog item" && fail "fire query catches backlog"
backlog_rows="$(sqlite3 "$DB" "SELECT title FROM reminders WHERE done = 0 AND due_at IS NULL;")"
echo "$backlog_rows" | grep -q "backlog item" || fail "backlog query misses the dateless row"
tasks_order="$(sqlite3 "$DB" "SELECT title FROM reminders WHERE done = 0 ORDER BY due_at IS NULL, due_at;")"
[ "$(echo "$tasks_order" | tail -n 1)" = "backlog item" ] || fail "tasks order puts backlog before dated rows"
pass "dateless rows stay out of date bounds and the fire query, last in tasks"

# Fire simulation: what applyDueReminders queues for a due once row.
sqlite3 "$DB" "UPDATE reminders SET done = 1 WHERE title = 'evening item'; INSERT INTO reminder_events (reminder_id, kind) VALUES ((SELECT id FROM reminders WHERE title = 'evening item'), 'fired');"
[ "$(sqlite3 "$DB" "SELECT done FROM reminders WHERE title = 'evening item';")" = "1" ] || fail "fire did not mark done"
[ "$(sqlite3 "$DB" "SELECT count(*) FROM reminder_events WHERE kind = 'fired';")" = "1" ] || fail "fire left no audit row"
pass "firing marks done and leaves an audit row"

# Guardrail on the agent doc (the read-back rule itself lands via #33).
grep -q "date -d 'tomorrow 00:00'" "$ROOT/opencode/agents/frieren.md" || fail "agent doc lost the date-based bound"
pass "agent doc keeps the date-based bound"

echo "all reminders tests passed"
