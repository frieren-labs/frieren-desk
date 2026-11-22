#!/usr/bin/env bash
# Frieren activity hook.
#
# The shell pipes one JSON event per line on stdin for every finished turn and
# every finished tool call. The raw stream is always appended to events.jsonl;
# when sqlite3 is available the same rows are written to frieren.db so a
# dashboard can query them.
#
# Location: ~/.config/quickshell/frieren/hooks/frieren-log.sh
# Tables:   turns (one row per question), tools (one row per tool call)
# View:     daily (per-day success rate and average duration)
#
# Disable it from the tray menu (Settings → Activity log) or with
#   qs -c frieren ipc call frieren log false
set -uo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/frieren"
DB="$STATE/frieren.db"
LOG="$STATE/events.jsonl"

mkdir -p "$STATE" 2>/dev/null || exit 0

line="$(head -n 1)"
[ -n "$line" ] || exit 0

# Keep the raw stream even without sqlite3: it can be replayed later.
printf '%s\n' "$line" >> "$LOG" 2>/dev/null || true

# Rotate the raw log so it does not grow without bound. Keep the last
# ~5000 lines once it passes ~5 MB. frieren.db is independent and safe.
if [ -f "$LOG" ]; then
  size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  if [ "${size:-0}" -gt 5242880 ]; then
    tail -n 5000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" || true
  fi
fi

command -v sqlite3 >/dev/null 2>&1 || exit 0

# The event is a JSON object; quote it once and let SQLite read the fields with
# json_extract. Only single quotes need escaping in a SQL string literal.
json="${line//\'/\'\'}"

sqlite3 "$DB" >/dev/null 2>&1 <<SQL || true
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
CREATE TABLE IF NOT EXISTS turns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL,
    session TEXT,
    prompt TEXT,
    duration_ms INTEGER,
    exit_code INTEGER,
    ok INTEGER,
    tools_total INTEGER,
    tools_failed INTEGER,
    error TEXT,
    model TEXT
);
CREATE TABLE IF NOT EXISTS tools (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL,
    session TEXT,
    tool TEXT,
    command TEXT,
    status TEXT,
    ok INTEGER,
    duration_ms INTEGER
);
CREATE INDEX IF NOT EXISTS turns_ts ON turns(ts);
CREATE INDEX IF NOT EXISTS tools_ts ON tools(ts);
CREATE VIEW IF NOT EXISTS daily AS
    SELECT substr(ts, 1, 10) AS day,
           count(*) AS turns,
           sum(ok) AS ok_turns,
           round(100.0 * sum(ok) / count(*), 1) AS ok_pct,
           round(avg(duration_ms)) AS avg_ms,
           sum(tools_failed) AS tool_failures
    FROM turns
    GROUP BY day;
INSERT INTO turns (ts, session, prompt, duration_ms, exit_code, ok,
                   tools_total, tools_failed, error, model)
SELECT json_extract('$json', '$.ts'),
       json_extract('$json', '$.session'),
       json_extract('$json', '$.prompt'),
       json_extract('$json', '$.duration_ms'),
       json_extract('$json', '$.exit_code'),
       json_extract('$json', '$.ok'),
       json_extract('$json', '$.tools_total'),
       json_extract('$json', '$.tools_failed'),
       json_extract('$json', '$.error'),
       json_extract('$json', '$.model')
WHERE json_extract('$json', '$.event') = 'turn';
INSERT INTO tools (ts, session, tool, command, status, ok, duration_ms)
SELECT json_extract('$json', '$.ts'),
       json_extract('$json', '$.session'),
       json_extract('$json', '$.tool'),
       json_extract('$json', '$.command'),
       json_extract('$json', '$.status'),
       json_extract('$json', '$.ok'),
       json_extract('$json', '$.duration_ms')
WHERE json_extract('$json', '$.event') = 'tool';
SQL
