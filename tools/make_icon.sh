#!/usr/bin/env bash
set -euo pipefail

# Build the Frieren tray icon from the idle pose.
#
# Outputs:
#   assets/frieren-icon.png       128x128 preview / IconName fallback
#   assets/frieren-icon-128.argb  raw A,R,G,B bytes for the StatusNotifierItem
#   assets/frieren-icon-64.argb
#   assets/frieren-icon-32.argb
#
# Requires ImageMagick (magick or convert), xxd and sed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$ROOT/quickshell/frieren/assets"
SOURCE="$ASSETS/poses/idle.png"
OUT="$ASSETS"

usage() {
    cat <<'EOF'
Usage: tools/make_icon.sh [--source PATH] [--out DIR]

  --source PATH   idle pose to crop (default: assets/poses/idle.png)
  --out DIR       output directory (default: assets)
  -h, --help      show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --source)
            [ $# -ge 2 ] || { echo "error: --source needs a path" >&2; exit 2; }
            SOURCE="$2"
            shift 2
            ;;
        --out)
            [ $# -ge 2 ] || { echo "error: --out needs a path" >&2; exit 2; }
            OUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if command -v magick >/dev/null 2>&1; then
    IM=magick
elif command -v convert >/dev/null 2>&1; then
    IM=convert
else
    echo "error: ImageMagick is required (magick or convert)." >&2
    exit 1
fi

command -v xxd >/dev/null 2>&1 || {
    echo "error: xxd is required (package: vim-common)." >&2
    exit 1
}

[ -f "$SOURCE" ] || {
    echo "error: source pose not found: $SOURCE" >&2
    exit 1
}

mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Head crop inside the 228x256 idle pose.
"$IM" "$SOURCE" -crop 144x136+46+14 +repage "$TMP/head.png"

# 2. Fit the head inside 86% of the icon, centred.
"$IM" "$TMP/head.png" -resize 110x110 -background none \
    -gravity center -extent 110x110 "$TMP/head-square.png"

# 3. Circular badge: dark surface with an accent ring.
"$IM" -size 128x128 xc:none \
    -fill '#211f24' -stroke '#d0bcff' -strokewidth 3 \
    -draw 'ellipse 63.5,63.5 62.5,62.5 0,360' "$TMP/badge.png"

# 4. Compose the final icon.
"$IM" "$TMP/badge.png" "$TMP/head-square.png" \
    -gravity center -geometry +0+2 -composite \
    -depth 8 -strip -define png:compression-level=9 "$OUT/frieren-icon.png"

# 5. Raw A,R,G,B bytes for the tray helper.
#    rgba: writes R,G,B,A; the sed rotation turns each pixel into A,R,G,B.
for size in 128 64 32; do
    "$IM" "$OUT/frieren-icon.png" -resize "${size}x${size}" -depth 8 rgba:- \
        | xxd -p -c 4 \
        | sed -E 's/(..)(..)(..)(..)/\4\1\2\3/' \
        | xxd -r -p > "$OUT/frieren-icon-$size.argb"
done

echo "icon:  $OUT/frieren-icon.png"
echo "argb:  $OUT/frieren-icon-128.argb, $OUT/frieren-icon-64.argb, $OUT/frieren-icon-32.argb"
