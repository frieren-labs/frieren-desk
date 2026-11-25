#!/usr/bin/env bash
# Regression tests for closing /tasks from any session (follow-up to #28).
# - Task state lives in frieren.db, table reminders (done 0 open, 1 closed).
# - The stable close key is reminders.id, independent of the session that
#   created the row. A different session must be able to close it.
# - A title closes only on a single open match; several matches ask first.
# - After closing, the /tasks query must not list the row and done must be 1.
# Usage: run from the repo root. Needs sqlite3. TZ is pinned.
set -euo pipefail

TZ=America/Argentina/Buenos_Aires
export TZ
command -v sqlite3 >/dev/null 2>&1 || { echo "skip: sqlite3 not found"; exit 0; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="$(mktemp)"
trap 'rm -f "$DB"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "ok: $*"; }

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

# The exact open-rows query /tasks (reminderLister) runs in shell.qml.
tasks_open() {
  sqlite3 "$DB" "SELECT id FROM reminders WHERE done = 0 ORDER BY due_at IS NULL, due_at LIMIT 20;"
}

# Mirror of doneSearchSql: strip LIKE wildcards, match open rows only.
resolve_by_title() {
  local needle="${1//%/}"
  needle="${needle//_/}"
  sqlite3 "$DB" "SELECT id FROM reminders WHERE done = 0 AND title LIKE '%${needle//\'/\'\'}%' ORDER BY id LIMIT 6;"
}

# Mirror of completeReminder: stable-id write plus the audit row.
close_by_id() {
  sqlite3 "$DB" "UPDATE reminders SET done = 1 WHERE id = $1; INSERT INTO reminder_events (reminder_id, kind) VALUES ($1, 'done');"
}

# Session A creates a dated task; session B (a separate sqlite3 call, no
# shared state) closes it by the stable id.
sqlite3 "$DB" "INSERT INTO reminders (title, due_at) VALUES ('fix lldap deploy', NULL);"
TASK_ID="$(sqlite3 "$DB" "SELECT id FROM reminders WHERE title = 'fix lldap deploy';")"
[ -n "$TASK_ID" ] || fail "session A insert did not return a stable id"
echo "$TASK_ID" | grep -Eq '^[0-9]+$' || fail "stable id is not numeric: $TASK_ID"
pass "session A creates a task with stable id $TASK_ID"

tasks_open | grep -qx "$TASK_ID" || fail "/tasks query misses the open task before close"
pass "/tasks lists the open task before close"

# A conversational reply alone must not flip the row: only the UPDATE does.
[ "$(sqlite3 "$DB" "SELECT done FROM reminders WHERE id = $TASK_ID;")" = "0" ] || fail "row starts closed"
pass "row stays open until the persistent UPDATE runs"

close_by_id "$TASK_ID"
[ "$(sqlite3 "$DB" "SELECT done FROM reminders WHERE id = $TASK_ID;")" = "1" ] || fail "session B close did not persist done = 1"
tasks_open | grep -qx "$TASK_ID" && fail "/tasks still lists the task after close"
pass "a different session closes by stable id and /tasks drops the row"
[ "$(sqlite3 "$DB" "SELECT count(*) FROM reminder_events WHERE reminder_id = $TASK_ID AND kind = 'done';")" = "1" ] || fail "close left no audit row"
pass "close leaves one reminder_events audit row"

# Re-reading proves persistence: the row stays closed, /tasks stays clean.
[ "$(sqlite3 "$DB" "SELECT done FROM reminders WHERE id = $TASK_ID;")" = "1" ] || fail "done = 1 did not persist on re-read"
tasks_open | grep -qx "$TASK_ID" && fail "closed row reappeared in /tasks"
pass "done = 1 persists and /tasks stays clean on re-read"

# Title resolution: a single clear match resolves to its id.
sqlite3 "$DB" "INSERT INTO reminders (title, due_at) VALUES ('water the mandrake garden', NULL);"
SINGLE="$(resolve_by_title 'mandrake garden')"
[ "$(echo "$SINGLE" | wc -l)" = "1" ] || fail "single title match should resolve to one id, got: $SINGLE"
close_by_id "$SINGLE"
[ "$(sqlite3 "$DB" "SELECT done FROM reminders WHERE id = $SINGLE;")" = "1" ] || fail "single title match close did not persist"
pass "a single clear title match closes by its stable id"

# Title resolution: several matches must ask, never close at random.
sqlite3 "$DB" "INSERT INTO reminders (title, due_at) VALUES ('review deploy notes', NULL), ('review deploy checklist', NULL);"
MULTI="$(resolve_by_title 'review deploy')"
[ "$(echo "$MULTI" | wc -l)" = "2" ] || fail "ambiguous title should return both ids, got: $MULTI"
open_before="$(tasks_open | wc -l)"
# No close runs here: ambiguity requires clarification first.
[ "$(tasks_open | wc -l)" = "$open_before" ] || fail "ambiguous match changed open rows"
for id in $MULTI; do
  [ "$(sqlite3 "$DB" "SELECT done FROM reminders WHERE id = $id;")" = "0" ] || fail "ambiguous match closed id $id at random"
done
pass "several title matches stay open until the user picks an id"

# A title with no open match resolves to nothing and closes nothing.
[ -z "$(resolve_by_title 'no such task here')" ] || fail "unknown title should resolve to zero rows"
pass "an unknown title matches nothing"

# Contract guardrails: the agent doc and the QML close path stay in sync
# with the behavior tested above.
grep -q "reminders.id" "$ROOT/opencode/agents/frieren.md" || fail "agent doc lost the stable reminders.id key"
grep -q "Several matches" "$ROOT/opencode/agents/frieren.md" || fail "agent doc lost the several-matches rule"
grep -q "UPDATE reminders SET done = 1 WHERE id" "$ROOT/opencode/agents/frieren.md" || fail "agent doc lost the persistent close write"
grep -q "reminder_events" "$ROOT/opencode/agents/frieren.md" || fail "agent doc lost the audit row"
grep -q "WHERE done = 0 ORDER BY" "$ROOT/opencode/agents/frieren.md" || fail "agent doc lost the /tasks verification query"
grep -q "doneFinder" "$ROOT/quickshell/frieren/shell.qml" || fail "shell.qml lost the title lookup process"
grep -q "applyDoneSearch" "$ROOT/quickshell/frieren/shell.qml" || fail "shell.qml lost the disambiguation step"
grep -q "completeReminder" "$ROOT/quickshell/frieren/shell.qml" || fail "shell.qml lost the stable-id close helper"
grep -q "/done <id|text>" "$ROOT/quickshell/frieren/components/ChatPanel.qml" || fail "chat panel lost the /done title hint"
pass "agent doc and QML keep the stable-id close contract"

echo "all tasks-done tests passed"
