#!/usr/bin/env bash
# Frieren voice manager: list, download and select piper voices.
#
#   frieren-voice list              installed (*) + downloadable catalog
#   frieren-voice download <id>     fetch onnx + json into the voices dir
#   frieren-voice use <id>          set voiceId in settings.json (enables voice)
#
# Voices live in ${XDG_DATA_HOME:-$HOME/.local/share}/frieren/voice/voices/
# as <id>.onnx + <id>.onnx.json. The legacy en.onnx still works as fallback.
set -euo pipefail

DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
VOICE_DIR="$DATA/frieren/voice/voices"
LEGACY="$DATA/frieren/voice/en.onnx"
SETTINGS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/frieren"
SETTINGS="$SETTINGS_DIR/settings.json"
BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main"

catalog() {
  cat <<'EOF'
en-jenny|en/en_GB/jenny_dioco/medium/en_GB-jenny_dioco-medium|English (GB, female)
en-lessac|en/en_US/lessac/medium/en_US-lessac-medium|English (US, female)
es-daniela|es/es_AR/daniela/high/es_AR-daniela-high|Spanish (AR, female)
EOF
}

url_of() {
  local id="$1" path
  path="$(catalog | awk -F'|' -v id="$id" '$1 == id { print $2 }')"
  [ -n "$path" ] || return 1
  printf '%s' "$path"
}

cmd="${1:-list}"
arg="${2:-}"

case "$cmd" in
  list)
    echo "installed (* = legacy en.onnx):"
    if [ -d "$VOICE_DIR" ]; then
      for f in "$VOICE_DIR"/*.onnx; do
        [ -e "$f" ] || continue
        [ -f "${f}.json" ] || continue
        echo "  $(basename "$f" .onnx)"
      done
    fi
    [ -f "$LEGACY" ] && echo "  en.onnx (legacy)"
    echo "downloadable:"
    catalog | while IFS='|' read -r id _ label; do
      if [ -f "$VOICE_DIR/$id.onnx" ]; then echo "  $id  $label  [downloaded]";
      else echo "  $id  $label"; fi
    done
    ;;
  download)
    [ -n "$arg" ] || { echo "usage: frieren-voice download <id>" >&2; exit 1; }
    path="$(url_of "$arg")" || { echo "unknown voice: $arg" >&2; exit 1; }
    mkdir -p "$VOICE_DIR"
    echo "downloading $arg..."
    curl -fSL -o "$VOICE_DIR/$arg.onnx" "$BASE/$path.onnx" || exit 1
    curl -fSL -o "$VOICE_DIR/$arg.onnx.json" "$BASE/$path.onnx.json" || exit 1
    echo "saved to $VOICE_DIR/$arg.onnx"
    ;;
  use)
    [ -n "$arg" ] || { echo "usage: frieren-voice use <id>" >&2; exit 1; }
    if [ ! -f "$VOICE_DIR/$arg.onnx" ] && [ "$arg.onnx" != "$(basename "$LEGACY")" ]; then
      echo "not downloaded: $arg (run: frieren-voice download $arg)" >&2
      exit 1
    fi
    mkdir -p "$SETTINGS_DIR"
    python3 - "$SETTINGS" "$arg" <<'EOF'
import json, sys
path, vid = sys.argv[1], sys.argv[2]
try:
    with open(path) as f: doc = json.load(f)
    assert isinstance(doc, dict)
except (OSError, ValueError, AssertionError):
    doc = {}
doc["voiceId"] = vid
doc["voice"] = True
with open(path, "w") as f: json.dump(doc, f, indent=2, ensure_ascii=False)
print("voice: " + vid)
EOF
    ;;
  *)
    echo "usage: frieren-voice [list|download <id>|use <id>]" >&2
    exit 1
    ;;
esac
