#!/usr/bin/env bash
# frieren-weekly: generate a short Spanish weekly review from frieren.db stats.
# Usage: frieren-weekly.sh
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/frieren"
DB="$STATE/frieren.db"
STATE_JSON="$STATE/state.json"
MODEL_DEFAULT="opencode-go/deepseek-v4.1-flash"

# CONFIG/DATA are defined for convention; STATE/DB/STATE_JSON carry the logic.

command -v sqlite3 >/dev/null 2>&1 || { echo "error: sqlite3 not found" >&2; exit 1; }
[ -f "$DB" ] || { echo "error: no database at $DB" >&2; exit 1; }

# Tolerate a fresh DB that only has history tables so far.
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
SQL

DAILY="$(sqlite3 -header -column "$DB" "SELECT substr(ts,1,10) AS day, count(*) AS turns, round(100.0*sum(ok)/count(*),1) AS ok_pct, round(avg(duration_ms)) AS avg_ms FROM turns WHERE ts >= date('now','-7 days') GROUP BY day ORDER BY day DESC;" || true)"
TOTALS="$(sqlite3 -header -column "$DB" "SELECT count(*) AS turns, round(100.0*sum(ok)/count(*),1) AS ok_pct, round(avg(duration_ms)) AS avg_ms FROM turns WHERE ts >= date('now','-7 days');" || true)"
FAILS="$(sqlite3 -header -column "$DB" "SELECT command, count(*) AS fails FROM tools WHERE ok = 0 AND ts >= date('now','-7 days') GROUP BY command ORDER BY fails DESC LIMIT 5;" || true)"
SLOW="$(sqlite3 -header -column "$DB" "SELECT substr(prompt,1,60) AS prompt, duration_ms FROM turns WHERE ts >= date('now','-7 days') ORDER BY duration_ms DESC LIMIT 5;" || true)"

MODEL="$MODEL_DEFAULT"
if [ -f "$STATE_JSON" ]; then
  MODEL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("model","") or "")' "$STATE_JSON" 2>/dev/null || true)"
  [ -n "${MODEL:-}" ] || MODEL="$MODEL_DEFAULT"
fi

STATS="Daily (last 7 days):
$DAILY

Totals (last 7 days):
$TOTALS

Top 5 failing commands:
$FAILS

Slowest 5 turns:
$SLOW"

PROMPT="Resume en 5 lineas en espanol esta semana de uso del asistente: que mejoro respecto a los ultimos dias, cual fue el fallo principal y una sugerencia concreta. Datos:
$STATS"

OUT=""
if command -v opencode >/dev/null 2>&1; then
  RAW="$(opencode run --format json --model "$MODEL" "$PROMPT" 2>/dev/null || true)"
  if [ -n "${RAW:-}" ]; then
    OUT="$(printf '%s\n' "$RAW" | python3 -c '
import json, sys
texts = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    if ev.get("type") == "text" and isinstance(ev.get("part"), dict):
        t = ev["part"].get("text", "")
        if t:
            texts.append(t)
print("".join(texts))
' || true)"
  fi
fi

if [ -n "${OUT:-}" ]; then
  printf '%s\n' "$OUT"
  exit 0
fi

echo "$STATS"
echo ""
echo "Prompt para el chat:"
echo "$PROMPT"
exit 0
