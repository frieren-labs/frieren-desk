#!/usr/bin/env bash
# Launch Frieren from the application menu (or from a terminal).
#
# If the shell is already running, open or close the chat. Otherwise start the
# pet detached and open the chat once the IPC answers.
set -euo pipefail

CONFIG="frieren"

if ! command -v qs >/dev/null 2>&1; then
    echo "error: quickshell is missing (package: quickshell, binary: qs)" >&2
    exit 1
fi

if qs -c "$CONFIG" ipc call "$CONFIG" ping >/dev/null 2>&1; then
    exec qs -c "$CONFIG" ipc call "$CONFIG" toggle
fi

# -n: exit if another instance is already running, -d: detach from the menu.
qs -c "$CONFIG" -n -d

# The IPC socket takes a moment to appear on a cold start.
for _ in $(seq 1 50); do
    if qs -c "$CONFIG" ipc call "$CONFIG" ping >/dev/null 2>&1; then
        exec qs -c "$CONFIG" ipc call "$CONFIG" toggle
    fi
    sleep 0.1
done

echo "warning: frieren started but the IPC did not answer" >&2
