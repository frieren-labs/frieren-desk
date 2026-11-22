#!/usr/bin/env bash
# Frieren voice helper (internal, called from shell.qml).
# Reads the prompt text on stdin, speaks it aloud, exits 0 on success.
# Usage: frieren-say.sh [voice-id] [volume-percent]   (defaults: en-jenny 100)
#
# Voice files: $DATA/frieren/voice/voices/<id>.onnx (+ .json), with the
# legacy $DATA/frieren/voice/en.onnx as fallback.
# Backend order: piper / piper-tts (with a model file) then espeak-ng,
# espeak, spd-say. Volume is applied with ffmpeg when it is not 100
# (needs ffmpeg installed, otherwise plays at full volume).
# Without any backend it exits 2.
set -euo pipefail

DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
VOICE_DIR="$DATA/frieren/voice/voices"
VOICE_ID="${1:-en-jenny}"
VOLUME="${2:-100}"
MODEL="$VOICE_DIR/$VOICE_ID.onnx"
[ -f "$MODEL" ] || MODEL="$DATA/frieren/voice/en.onnx"

text="$(head -c 600)"
[ -n "$text" ] || exit 0
# Strip code fences and markdown noise before speaking.
clean="$(printf '%s' "$text" | sed -e 's/```//g' -e 's/^[#>*-] *//' \
  -e 's/[*_`~]//g' | tr '\n' ' ' | head -c 600)"
[ -n "$clean" ] || exit 0

play_wav() {
  if command -v paplay >/dev/null 2>&1; then paplay "$1" 2>/dev/null;
  elif command -v aplay >/dev/null 2>&1; then aplay -q "$1" 2>/dev/null;
  elif command -v ffplay >/dev/null 2>&1; then
    ffplay -nodisp -autoexit -loglevel quiet "$1" 2>/dev/null;
  else return 1; fi
}

# Software volume: scale the wav with ffmpeg (10-150%). Without ffmpeg,
# or at 100, the file plays untouched.
apply_volume() {
  case "$VOLUME" in ''|*[!0-9]*) VOLUME=100 ;; esac
  [ "$VOLUME" -ge 10 ] 2>/dev/null || VOLUME=10
  [ "$VOLUME" -le 150 ] 2>/dev/null || VOLUME=150
  [ "$VOLUME" = "100" ] && return 0
  command -v ffmpeg >/dev/null 2>&1 || return 0
  command -v awk >/dev/null 2>&1 || return 0
  local factor out="$1.scaled.wav"
  factor="$(awk -v v="$VOLUME" 'BEGIN { printf "%.3f", v / 100 }')"
  ffmpeg -y -v error -i "$1" -filter:a "volume=$factor" "$out" || return 0
  mv -f "$out" "$1"
}

PIPER=""
if command -v piper >/dev/null 2>&1; then PIPER="piper";
elif command -v piper-tts >/dev/null 2>&1; then PIPER="piper-tts"; fi

if [ ! -f "$MODEL" ]; then
  echo "voice '$VOICE_ID' is not downloaded. Run: frieren-voice download $VOICE_ID" >&2
  exit 2
fi

if [ -n "$PIPER" ] && [ -f "$MODEL" ]; then
  out="$(mktemp --suffix=.wav)"
  trap 'rm -f "$out"' EXIT
  printf '%s' "$clean" | "$PIPER" --model "$MODEL" --output_file "$out" \
    >/dev/null 2>&1 || exit 3
  apply_volume "$out"
  play_wav "$out" || exit 3
  exit 0
fi

if command -v espeak-ng >/dev/null 2>&1; then
  exec espeak-ng "$clean" >/dev/null 2>&1
elif command -v espeak >/dev/null 2>&1; then
  exec espeak "$clean" >/dev/null 2>&1
elif command -v spd-say >/dev/null 2>&1; then
  exec spd-say "$clean" >/dev/null 2>&1
fi

echo "no voice engine found. Install one: paru -S piper-tts (then frieren-voice list), or espeak-ng for a basic voice." >&2
exit 2
