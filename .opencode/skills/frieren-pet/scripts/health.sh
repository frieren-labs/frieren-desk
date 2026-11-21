#!/usr/bin/env bash
# Check the running Frieren shell, state file and tray helper.
set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/frieren"
state_file="$state_dir/state.json"
fail=0

if ! command -v qs >/dev/null 2>&1; then
  echo "qs: not found in PATH" >&2
  exit 1
fi

if qs -c frieren ipc call frieren ping 2>/dev/null | grep -q pong; then
  echo "ipc: ok"
else
  echo "ipc: no response from 'qs -c frieren'" >&2
  fail=1
fi

if [ -r "$state_file" ]; then
  echo "state: $state_file"
  sed 's/,/,\n  /g; s/^/  /' "$state_file" | sed '1s/^  //'
  echo
else
  echo "state: missing or unreadable at $state_file" >&2
  fail=1
fi

if pgrep -f "frieren/tray.py" >/dev/null 2>&1; then
  echo "tray: helper is running"
else
  echo "tray: helper is not running" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "Hint: run scripts/restart.sh and check the foreground logs with 'qs -c frieren'." >&2
fi

exit "$fail"
