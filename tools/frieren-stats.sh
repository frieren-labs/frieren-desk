#!/usr/bin/env bash
# Frieren stats: reads frieren.db and prints a small dashboard.
# Usage: frieren-stats.sh [--json] [days]
set -uo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/frieren"
DB="$STATE/frieren.db"
DAYS="${1:-14}"
JSON=0
if [ "${1:-}" = "--json" ]; then
  JSON=1
  DAYS="${2:-14}"
fi

command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 not found" >&2; exit 1; }
[ -f "$DB" ] || { echo "no database at $DB" >&2; exit 1; }

# Ensure the activity tables exist: a fresh frieren.db may only have the
# history tables (conversations, messages) until the first turn is logged.
sqlite3 "$DB" >/dev/null 2>&1 <<'SQL' || true
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
SQL

if [ "$JSON" = "1" ]; then
  sqlite3 -json "$DB" "SELECT * FROM daily ORDER BY day DESC LIMIT $DAYS;"
  exit 0
fi

echo "== Frieren · last $DAYS days =="
sqlite3 -header -column "$DB" "SELECT * FROM daily ORDER BY day DESC LIMIT $DAYS;"
echo ""
echo "== Totals (all time) =="
sqlite3 -header -column "$DB" "SELECT count(*) AS turns, sum(ok) AS ok, round(100.0*sum(ok)/count(*),1) AS ok_pct, round(avg(duration_ms)) AS avg_ms FROM turns;"
echo ""
echo "== Top failing commands =="
sqlite3 -header -column "$DB" "SELECT command, count(*) AS fails FROM tools WHERE ok = 0 GROUP BY command ORDER BY fails DESC LIMIT 10;"
echo ""
echo "== Slowest turns =="
sqlite3 -header -column "$DB" "SELECT substr(prompt,1,60) AS prompt, duration_ms FROM turns ORDER BY duration_ms DESC LIMIT 10;"
