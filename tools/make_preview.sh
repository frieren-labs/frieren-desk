#!/usr/bin/env bash
# Regenerates assets/poses-preview.png from the real pose sprites.
# 4x2 cards in the README showcase style: sprite + chat bubble + label + dot.
set -euo pipefail
cd "$(dirname "$0")/.."

# NOTE: happy appears twice below on purpose? No - list is explicit:
POSES=(idle think cast reading happy celebrate sad sleep)
TEXTS=("ask me something" "thinking…" "casting a spell…" "reading…" "done" "amazing!" "oops…" "zzz…")
DOTS=("b898ff" "cfb8ff" "cfb8ff" "7fd8ff" "ffd97f" "a8ff7f" "ff9d9d" "7fb8ff")
LABELS=(IDLE THINK CAST READING HAPPY CELEBRATE SAD SLEEP)

CELL_W=470
CELL_H=300
GAP=24
COLS=4
ROWS=2
BG="#101014"
CARD="#1d1b22"
BUBBLE="#2c2f36"
FG="#e8e6ea"
DIM="#8b8794"

W=$((COLS * CELL_W + (COLS + 1) * GAP))
H=$((ROWS * CELL_H + (ROWS + 1) * GAP))

build_card() { # $1=pose $2=text $3=dot $4=label -> $5=out
  local pose="$1" text="$2" dot="$3" label="$4" out="$5"
  local sprite="quickshell/frieren/assets/poses/${pose}.png"
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

i=0
for pose in "${POSES[@]}"; do
  build_card "$pose" "${TEXTS[$i]}" "${DOTS[$i]}" "${LABELS[$i]}" "/tmp/opencode/card-$pose.png"
  i=$((i+1))
done

magick /tmp/opencode/card-idle.png /tmp/opencode/card-think.png /tmp/opencode/card-cast.png /tmp/opencode/card-reading.png \
  +append /tmp/opencode/row1.png
magick /tmp/opencode/card-happy.png /tmp/opencode/card-celebrate.png /tmp/opencode/card-sad.png /tmp/opencode/card-sleep.png \
  +append /tmp/opencode/row2.png
# gaps between cards and around: rebuild on background canvas
magick -size ${W}x${H} xc:"$BG" /tmp/opencode/canvas.png
x=$GAP; y=$GAP; n=0
for pose in "${POSES[@]}"; do
  col=$((n % COLS)); row=$((n / COLS))
  x=$((GAP + col * (CELL_W + GAP))); y=$((GAP + row * (CELL_H + GAP)))
  magick /tmp/opencode/canvas.png /tmp/opencode/card-$pose.png -geometry +${x}+${y} -compose over -composite /tmp/opencode/canvas.png
  n=$((n+1))
done
cp /tmp/opencode/canvas.png assets/poses-preview.png
identify assets/poses-preview.png
