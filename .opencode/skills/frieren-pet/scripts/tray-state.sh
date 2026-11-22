#!/usr/bin/env bash
# Print the toggle state of the Frieren DBusMenu entries.
set -euo pipefail

if ! command -v gdbus >/dev/null 2>&1; then
  echo "gdbus: not found in PATH" >&2
  exit 1
fi

# 7 Wander, 8 Sleep when idle, 9 Blink, 11 Small, 12 Medium, 13 Large,
# 18 Activity log.
gdbus call --session \
  --dest org.kde.StatusNotifierItem-frieren \
  --object-path /MenuBar \
  --method com.canonical.dbusmenu.GetGroupProperties \
  "[7,8,9,18,11,12,13]" "[]" \
  | sed 's/), (/)\n(/g'
