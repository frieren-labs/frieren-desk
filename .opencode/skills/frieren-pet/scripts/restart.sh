#!/usr/bin/env bash
# Restart the Frieren Quickshell instance through IPC.
set -euo pipefail

if ! command -v qs >/dev/null 2>&1; then
  echo "qs: not found in PATH" >&2
  exit 1
fi

if qs -c frieren ipc call frieren ping >/dev/null 2>&1; then
  qs -c frieren ipc call frieren quit >/dev/null 2>&1 || true

  for _ in $(seq 1 40); do
    if ! qs -c frieren ipc call frieren ping >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
fi

# Older starts may have left duplicate instances. IPC quit only stops the one
# that answered, so terminate any remaining Frieren process before starting.
# Match the exact argv shape, not a substring: a shell command that mentions
# "qs -c frieren" must not be killed.
frieren_pids() {
  ps -eo pid=,args= | awk '$2 ~ /(^|\/)qs$/ && $3 == "-c" && $4 == "frieren" { print $1 }'
}

for pid in $(frieren_pids); do
  kill "$pid" 2>/dev/null || true
done

for _ in $(seq 1 40); do
  if [ -z "$(frieren_pids)" ]; then
    break
  fi
  sleep 0.25
done

# -n refuses to start a duplicate if a process is still shutting down.
qs -c frieren -n -d

for _ in $(seq 1 40); do
  if qs -c frieren ipc call frieren ping >/dev/null 2>&1; then
    echo "frieren: restarted"
    exit 0
  fi
  sleep 0.25
done

echo "frieren: did not answer after restart" >&2
echo "Run 'qs -c frieren' in the foreground to see the logs." >&2
exit 1
