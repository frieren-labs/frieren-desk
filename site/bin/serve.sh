#!/bin/sh
# Local preview for the Jekyll site. Syncs artwork from the repo
# (gitignored under site/assets, see site/README.md) and serves
# with an empty baseurl plus livereload.
set -eu

REPO_DIR="${REPO_DIR:-/repo}"
if [ ! -d "$REPO_DIR/assets" ]; then
  # Running outside docker from site/: repo root is the parent dir.
  REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
fi

mkdir -p assets/img/poses assets/audio assets/overlay

cp -f "$REPO_DIR/assets/hero-bg.jpg" assets/img/ 2>/dev/null || true
cp -f "$REPO_DIR"/assets/overlay/*.mp4 assets/overlay/ 2>/dev/null || true
cp -f "$REPO_DIR/assets/page-music.mp3" assets/audio/ 2>/dev/null || true
cp -f "$REPO_DIR"/assets/showcase/*.png assets/img/ 2>/dev/null || true
cp -f "$REPO_DIR/quickshell/frieren/assets/frieren-icon.png" assets/img/ 2>/dev/null || true
cp -f "$REPO_DIR"/quickshell/frieren/assets/poses/*.png assets/img/poses/ 2>/dev/null || true

exec jekyll serve -H 0.0.0.0 -p 4000 --baseurl "" --livereload --force_polling
