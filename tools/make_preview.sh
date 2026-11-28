#!/usr/bin/env bash
# Regenerates assets/poses-preview.png from the real pose sprites.
# Cards in the README showcase style: sprite + chat bubble + label + dot.
#
# Fully data-driven: pose files and hint lines come from
# quickshell/frieren/assets/poses/poses.json, so adding a new pose
# needs no script change. Labels are the uppercased pose name, texts
# are the first hint line of the mood (walk-1/walk-2 share walk;
# "…" when the mood has no hints, e.g. blink), and dot colors hash
# stably from the mood name.
set -euo pipefail
cd "$(dirname "$0")/.."

POSES_JSON="quickshell/frieren/assets/poses/poses.json"
POSES_DIR="quickshell/frieren/assets/poses"

CELL_W=470
CELL_H=300
GAP=24
BG="#101014"
CARD="#1d1b22"
BUBBLE="#2c2f36"
FG="#e8e6ea"
DIM="#8b8794"

# Stable dot palette; the mood name hashes to one of these.
DOTS=(b898ff cfb8ff 7fd8ff ffd97f a8ff7f ff9d9d 7fb8ff 8b8794)

# file<TAB>mood<TAB>text per line, in poses.json order.
mapfile -t CARDS < <(python3 - "$POSES_JSON" <<'EOF'
import json, re, sys
doc = json.load(open(sys.argv[1]))
poses = doc["poses"]
hints = doc.get("hints", {})
for pose, meta in poses.items():
    mood = re.sub(r"-\d+$", "", pose)
    lines = hints.get(mood) or []
    print(meta["file"] + "\t" + mood + "\t" + (lines[0] if lines else "…"))
EOF
)

N=${#CARDS[@]}
# Grid as square-ish as possible: cols = ceil(sqrt(n)).
COLS=$(python3 -c "import math, sys; print(math.isqrt(int(sys.argv[1]) - 1) + 1)" "$N")
ROWS=$(( (N + COLS - 1) / COLS ))
W=$((COLS * CELL_W + (COLS + 1) * GAP))
H=$((ROWS * CELL_H + (ROWS + 1) * GAP))

build_card() { # $1=sprite $2=text $3=dot $4=label -> $5=out
  local sprite="$1" text="$2" dot="$3" label="$4" out="$5"
  magick -size ${CELL_W}x${CELL_H} xc:"$CARD" \
    -fill "$CARD" -draw "roundrectangle 0,0 $((CELL_W-1)),$((CELL_H-1)) 24,24" \
    "$out.base.png"
  # sprite, scaled to height 200, placed left
  magick "$sprite" -resize x170 "$out.sprite.png"
  sw=$(identify -format "%w" "$out.sprite.png")
  # bubble width fits text
  magick -background none -fill "$FG" -font DejaVu-Sans -pointsize 24 label:"$text" "$out.label.png"
  tw=$(identify -format "%w" "$out.label.png")
  bw=$((tw + 48)); bh=56
  bx=$((24 + sw + 20)); by=$((45 + 85 - 30))
  # label bottom-left, dot bottom-right
  magick "$out.base.png" \
    "$out.sprite.png" -geometry +24+45 -compose over -composite \
    -fill "$BUBBLE" -draw "roundrectangle $bx,$by $((bx+bw-1)),$((by+bh-1)) 20,20" \
    "$out.label.png" -geometry +$((bx+24))+$((by+13)) -compose over -composite \
    -fill "$DIM" -font DejaVu-Sans -pointsize 17 -annotate +24+$((CELL_H-30)) "$label" \
    -fill "#$dot" -draw "circle $((CELL_W-32)),$((CELL_H-30)) $((CELL_W-26)),$((CELL_H-30))" \
    "$out"
  rm -f "$out.base.png" "$out.sprite.png" "$out.label.png"
}

n=0
for card in "${CARDS[@]}"; do
  IFS=$'\t' read -r file mood text <<<"$card"
  label=$(printf '%s' "${file%.png}" | tr '[:lower:]' '[:upper:]')
  idx=$(printf '%s' "$mood" | cksum | awk -v m="${#DOTS[@]}" '{print $1 % m}')
  build_card "$POSES_DIR/$file" "$text" "${DOTS[$idx]}" "$label" "/tmp/opencode/card-$n.png"
  n=$((n + 1))
done

# gaps between cards and around: rebuild on background canvas
magick -size ${W}x${H} xc:"$BG" /tmp/opencode/canvas.png
n=0
while [ "$n" -lt "$N" ]; do
  col=$((n % COLS)); row=$((n / COLS))
  x=$((GAP + col * (CELL_W + GAP))); y=$((GAP + row * (CELL_H + GAP)))
  magick /tmp/opencode/canvas.png /tmp/opencode/card-$n.png -geometry +${x}+${y} -compose over -composite /tmp/opencode/canvas.png
  n=$((n + 1))
done
cp /tmp/opencode/canvas.png assets/poses-preview.png
rm -f /tmp/opencode/card-*.png
identify assets/poses-preview.png
