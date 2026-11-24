#!/usr/bin/env bash
# Frieren notifier: local notify-send plus an optional Discord webhook embed.
# Called from shell.qml (notifyTurn) and from the terminal for testing.
#
# Usage:
#   frieren-notify.sh "title" "body" [event]
#   frieren-notify.sh --test [--event done|error|reminder|backup|info]
#   frieren-notify.sh --dry-run "title" "body" [event]
#
# event selects the embed color and art. Default: info.
#
# Discord is opt-in: settings.json needs "discord": true. The webhook URL is
# never passed in argv (it would show up in ps). The script reads it from
# $DISCORD_WEBHOOK_URL or from ~/.config/frieren/discord-webhook.env
# (mode 600, either KEY=URL or a bare URL line).
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
ENV_FILE="$CONFIG/frieren/discord-webhook.env"
SETTINGS="$CONFIG/frieren/settings.json"

MODE="send"
EVENT="info"
TITLE="Frieren"
BODY=""

usage() {
  echo "usage: frieren-notify.sh \"title\" \"body\" [event]" >&2
  echo "       frieren-notify.sh --test [--event EVENT]" >&2
  echo "       frieren-notify.sh --dry-run \"title\" \"body\" [event]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --test) MODE="test"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    --event) EVENT="${2:-info}"; shift 2 ;;
    --event=*) EVENT="${1#--event=}"; shift ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "error: unknown flag: $1" >&2; usage ;;
    *)
      if [ "$TITLE" = "Frieren" ] && [ -z "$BODY" ] && [ "$#" -ge 1 ]; then
        TITLE="$1"; shift
        BODY="${1:-}"; [ $# -gt 0 ] && shift || true
        if [ $# -gt 0 ]; then EVENT="$1"; shift; fi
      else
        echo "error: unexpected argument: $1" >&2; usage
      fi
      ;;
  esac
done

case "$EVENT" in
  done|error|reminder|backup|info|test) ;;
  *) EVENT="info" ;;
esac
[ "$MODE" = "test" ] && [ "$TITLE" = "Frieren" ] && TITLE="Frieren test"
[ "$MODE" = "test" ] && [ -z "$BODY" ] && BODY="Discord webhook is configured. You will see reminders here when away from the PC."

# Local desktop notification first. It never depends on the network.
if command -v notify-send >/dev/null 2>&1; then
  notify-send "$TITLE" "$BODY" >/dev/null 2>&1 || true
fi

# Discord delivery happens in Python so the webhook URL stays out of argv
# and ps output. The payload travels over the Python process stdin.
[ "$MODE" = "dry-run" ] || [ "$MODE" = "test" ] || [ "$MODE" = "send" ] || usage

MODE="$MODE" TITLE="$TITLE" BODY="$BODY" EVENT="$EVENT" \
  ENV_FILE="$ENV_FILE" SETTINGS="$SETTINGS" python3 - <<'PYEOF'
import json
import os
import re
import stat
import sys
import urllib.request
from datetime import datetime, timezone

mode = os.environ.get("MODE", "send")
title = os.environ.get("TITLE", "Frieren")[:256]
body = os.environ.get("BODY", "")[:2000]
event = os.environ.get("EVENT", "info")
env_file = os.environ.get("ENV_FILE", "")
settings_path = os.environ.get("SETTINGS", "")

COLORS = {
    "done": 5763719,      # green
    "error": 15548997,    # red
    "reminder": 13623551, # frieren violet
    "backup": 5793266,    # blurple
    "info": 13623551,
    "test": 13623551,
}

POSE_BASE = ("https://raw.githubusercontent.com/jd-apprentice/"
             "frieren-desk/main/quickshell/frieren/assets/poses")
DEFAULT_POSES = {
    "done": POSE_BASE + "/happy.png",
    "error": POSE_BASE + "/sad.png",
    "reminder": POSE_BASE + "/think.png",
    "backup": POSE_BASE + "/reading.png",
    "info": POSE_BASE + "/idle.png",
    "test": POSE_BASE + "/happy.png",
}

url_pat = re.compile(r"https://discord(?:app)?\.com/api/webhooks/[A-Za-z0-9/_.\-]+")

webhook = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
if not webhook and env_file and os.path.isfile(env_file):
    st = os.stat(env_file)
    if st.st_mode & (stat.S_IRGRP | stat.S_IROTH | stat.S_IWGRP | stat.S_IWOTH):
        msg = ("webhook env file is readable by others: %s "
               "(run: chmod 600 %s)" % (env_file, env_file))
        if mode == "test":
            print("error: " + msg, file=sys.stderr)
            sys.exit(2)
        print("warning: " + msg + ", skipping Discord", file=sys.stderr)
    else:
        try:
            with open(env_file, "r", encoding="utf-8", errors="replace") as fh:
                found = url_pat.findall(fh.read())
            if found:
                webhook = found[0].rstrip("'\");,")
        except OSError as exc:
            print("warning: cannot read %s: %s" % (env_file, exc), file=sys.stderr)

settings = {}
if settings_path and os.path.isfile(settings_path):
    try:
        with open(settings_path, "r", encoding="utf-8") as fh:
            settings = json.load(fh)
    except (OSError, ValueError) as exc:
        print("warning: cannot parse settings.json: %s" % exc, file=sys.stderr)

enabled = settings.get("discord") is True

image = DEFAULT_POSES.get(event, DEFAULT_POSES["info"])
custom = settings.get("discordImages")
if isinstance(custom, dict) and isinstance(custom.get(event), str) and custom[event]:
    image = custom[event]
elif isinstance(settings.get("discordImage"), str) and settings["discordImage"]:
    image = settings["discordImage"]

embed = {
    "title": title or "Frieren",
    "description": body or "(no details)",
    "color": COLORS.get(event, COLORS["info"]),
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "footer": {"text": "frieren-desk"},
}
if image:
    embed["image"] = {"url": image}

payload = {"username": "Frieren", "embeds": [embed]}

if mode == "dry-run":
    print(json.dumps(payload, indent=2))
    sys.exit(0)

if not webhook:
    if mode == "test":
        print("error: no webhook URL found. Set DISCORD_WEBHOOK_URL or "
              "write it to %s" % env_file, file=sys.stderr)
        sys.exit(2)
    sys.exit(0)

if not enabled and mode == "send":
    sys.exit(0)

data = json.dumps(payload).encode("utf-8")
req = urllib.request.Request(
    webhook,
    data=data,
    headers={"Content-Type": "application/json",
             "User-Agent": "frieren-desk/1.0"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        status = resp.status
except Exception as exc:
    print("warning: Discord POST failed: %s" % exc, file=sys.stderr)
    sys.exit(1 if mode == "test" else 0)

if mode == "test":
    print("Discord: posted test embed (HTTP %s)." % status)
sys.exit(0)
PYEOF
