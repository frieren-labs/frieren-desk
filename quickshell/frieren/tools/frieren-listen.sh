#!/usr/bin/env bash
# Frieren dictation helper (internal, called from shell.qml).
#
#   frieren-listen.sh record <out.wav>      record mic until killed
#   frieren-listen.sh transcribe <in.wav>   print recognized text on stdout
#
# Recording uses the first available backend: pw-record, parecord, arecord.
# Transcription uses the first available engine: whisper, whisper-cli,
# faster-whisper. Without an engine it exits 3 with a hint on stderr.
set -euo pipefail

cmd="${1:-}"
file="${2:-}"

case "$cmd" in
  record)
    [ -n "$file" ] || { echo "missing output file" >&2; exit 1; }
    if command -v pw-record >/dev/null 2>&1; then
      exec pw-record --rate 16000 --channels 1 "$file"
    elif command -v parec >/dev/null 2>&1; then
      exec parec --rate=16000 --channels=1 --format=s16le "$file"
    elif command -v arecord >/dev/null 2>&1; then
      exec arecord -q -r 16000 -c 1 -f S16_LE "$file"
    else
      echo "no recorder found (install pipewire or alsa-utils)" >&2
      exit 2
    fi
    ;;
  transcribe)
    [ -n "$file" ] || { echo "missing input file" >&2; exit 1; }
    [ -f "$file" ] || { echo "nothing recorded" >&2; exit 1; }
    if command -v whisper >/dev/null 2>&1; then
      out="$(mktemp -d)"
      trap 'rm -rf "$out"' EXIT
      whisper "$file" --model tiny --output_format txt --output_dir "$out" \
        --verbose False >/dev/null 2>&1 || exit 3
      cat "$out"/*.txt
    elif command -v whisper-cli >/dev/null 2>&1; then
      model=""
      for cand in "$HOME/.cache/whisper/ggml-base.en.bin" \
        /usr/share/whisper/ggml-base.en.bin \
        "$HOME/.local/share/whisper/ggml-base.en.bin"; do
        [ -f "$cand" ] && model="$cand" && break
      done
      [ -n "$model" ] || { echo "whisper-cli needs a ggml model" >&2; exit 3; }
      whisper-cli -m "$model" -f "$file" --no-timestamps 2>/dev/null
    elif command -v faster-whisper >/dev/null 2>&1; then
      faster-whisper "$file" --model tiny --output_format txt 2>/dev/null
    else
      echo "no speech-to-text engine found (install openai-whisper or whisper.cpp)" >&2
      exit 3
    fi
    ;;
  *)
    echo "usage: frieren-listen.sh record|transcribe <file>" >&2
    exit 1
    ;;
esac
