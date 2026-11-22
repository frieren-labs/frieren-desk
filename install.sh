#!/usr/bin/env bash
# Frieren installer.
#
#   curl -fsSL https://raw.githubusercontent.com/jd-apprentice/frieren-desk/main/install.sh | bash
#   ./install.sh
#
# Options:
#   --force       overwrite ~/.config/opencode/agents/frieren.md
#   --uninstall   remove the installed files
#   --purge       with --uninstall, also delete ~/.local/state/frieren
#   -h, --help    show this help
#
# Environment:
#   FRIEREN_REPO  GitHub repo to download (default: jd-apprentice/frieren-desk)
#   FRIEREN_REF   branch, tag or commit to download (default: main)
set -euo pipefail

REPO="${FRIEREN_REPO:-jd-apprentice/frieren-desk}"
REF="${FRIEREN_REF:-main}"

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}"
QS_DIR="$CONFIG/quickshell/frieren"
OC_DIR="$CONFIG/opencode/agents"
APP_DIR="$DATA/applications"
ICON_DIR="$DATA/icons/hicolor/128x128/apps"
STATE_DIR="$STATE_BASE/frieren"
LAUNCHER="$BIN/frieren"
STATS="$BIN/frieren-stats"
ASKER="$BIN/frieren-ask"
SHOT="$BIN/frieren-shot"
BACKUPER="$BIN/frieren-backup"
WEEKLY="$BIN/frieren-weekly"
VOICER="$BIN/frieren-voice"

FORCE=0
UNINSTALL=0
PURGE=0
SCRATCH=""
ROOT=""
TRAY_TMP=""

usage() {
  cat <<'EOF'
Usage: install.sh [OPTIONS]

Installs the Frieren desktop pet: the Quickshell config, the app menu entry,
the launcher, the compiled tray helper and the opencode agent.

Options:
  --force       overwrite ~/.config/opencode/agents/frieren.md
  --uninstall   remove the installed files
  --purge       with --uninstall, also delete ~/.local/state/frieren
  -h, --help    show this help

Environment:
  FRIEREN_REPO  GitHub repo to download (default: jd-apprentice/frieren-desk)
  FRIEREN_REF   branch, tag or commit to download (default: main)

Build requirements: a C compiler, pkg-config and the gio-2.0 headers
(gcc, pkgconf and glib2 on Arch). The installer compiles the tray helper.

Runtime requirement: sqlite3 (package: sqlite on Arch) for the chat history
and the activity log in ~/.local/state/frieren/frieren.db.

When piped into bash, pass options with bash -s --:

  curl -fsSL .../install.sh | bash -s -- --force
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

note() {
  echo "  $*"
}

cleanup() {
  if [ -n "$SCRATCH" ]; then
    rm -rf "$SCRATCH"
  fi
  if [ -n "$TRAY_TMP" ]; then
    rm -f "$TRAY_TMP"
  fi
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --purge) PURGE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done

if [ "$PURGE" -eq 1 ] && [ "$UNINSTALL" -ne 1 ]; then
  die "--purge only works with --uninstall"
fi

refresh_caches() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$DATA/icons/hicolor" >/dev/null 2>&1 || true
  fi
}

uninstall() {
  echo "Removing Frieren..."
  qs -c frieren ipc call frieren quit >/dev/null 2>&1 || true
  rm -rf "$QS_DIR"
  rm -f "$LAUNCHER" "$STATS" "$ASKER" "$SHOT" "$BACKUPER" "$WEEKLY" "$VOICER" \
    "$APP_DIR/frieren.desktop" "$ICON_DIR/frieren.png" \
    "$OC_DIR/frieren.md"
  refresh_caches
  if [ "$PURGE" -eq 1 ]; then
    rm -rf "$STATE_DIR"
    note "state: $STATE_DIR removed"
  else
    note "state: $STATE_DIR kept (use --purge to remove it)"
  fi
  echo "Uninstalled. Remove the Frieren bind and autostart from your Hyprland"
  echo "config if you added them."
}

# The script can run from a clone or from a pipe. In the pipe case there is no
# checkout, so download the repository tarball and install from it.
locate_sources() {
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    return
  fi

  command -v tar >/dev/null 2>&1 || die "tar is required to download the release"
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || \
    die "curl or wget is required to download the release"

  local url tmp archive
  url="https://github.com/$REPO/archive/$REF.tar.gz"
  SCRATCH="$(mktemp -d)"
  archive="$SCRATCH/src.tar.gz"

  echo "Downloading $REPO ($REF)..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$archive" || die "download failed: $url"
  else
    wget -qO "$archive" "$url" || die "download failed: $url"
  fi

  tar -xzf "$archive" -C "$SCRATCH" || die "could not extract $archive"
  ROOT="$(find "$SCRATCH" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [ -n "$ROOT" ] || die "could not find the extracted sources"
}

if [ "$UNINSTALL" -eq 1 ]; then
  uninstall
  exit 0
fi

locate_sources

for file in quickshell/frieren/shell.qml quickshell/frieren/tray.c \
  quickshell/frieren/hooks/frieren-log.sh \
  quickshell/frieren/tools/frieren-listen.sh \
  quickshell/frieren/tools/frieren-say.sh \
  tools/frieren-launch.sh tools/frieren-stats.sh tools/frieren-ask.sh \
  tools/frieren-shot.sh tools/frieren-backup.sh tools/frieren-weekly.sh \
  tools/frieren-voice.sh opencode/agents/frieren.md; do
  [ -f "$ROOT/$file" ] || die "missing file in the release: $file"
done

command -v qs >/dev/null 2>&1 || \
  die "quickshell is missing (package: quickshell, binary: qs)"

command -v sqlite3 >/dev/null 2>&1 || \
  die "sqlite3 is required for chat history and the activity log (package: sqlite)"

command -v opencode >/dev/null 2>&1 || \
  echo "warning: opencode is not in PATH. The pet opens, but chat will not respond." >&2

# Compile before touching the config, so a failed build does not leave a
# half-installed tray.
TRAY_CC="${CC:-cc}"
command -v "$TRAY_CC" >/dev/null 2>&1 || \
  die "a C compiler is required for the tray (package: gcc or base-devel)"
command -v pkg-config >/dev/null 2>&1 || \
  die "pkg-config is required for the tray (package: pkgconf)"
pkg-config --exists gio-2.0 || \
  die "the gio headers are required for the tray (package: glib2)"

TRAY_TMP="$(mktemp)"
if ! "$TRAY_CC" -O2 -s -o "$TRAY_TMP" "$ROOT/quickshell/frieren/tray.c" \
  $(pkg-config --cflags gio-2.0) $(pkg-config --libs gio-2.0); then
  die "could not compile tray.c"
fi

echo "Installing Frieren..."
mkdir -p "$QS_DIR" "$OC_DIR" "$APP_DIR" "$ICON_DIR" "$BIN"
cp -R "$ROOT/quickshell/frieren/." "$QS_DIR/"
note "config: $QS_DIR"

install -m 755 "$ROOT/quickshell/frieren/hooks/frieren-log.sh" \
  "$QS_DIR/hooks/frieren-log.sh"
note "activity hook: $QS_DIR/hooks/frieren-log.sh"

install -m 755 "$TRAY_TMP" "$QS_DIR/frieren-tray"
rm -f "$TRAY_TMP"
TRAY_TMP=""
note "tray: native helper"

install -m 755 "$ROOT/tools/frieren-launch.sh" "$LAUNCHER"
note "launcher: $LAUNCHER"

install -m 755 "$ROOT/tools/frieren-stats.sh" "$STATS"
note "stats: $STATS"
install -m 755 "$ROOT/tools/frieren-ask.sh" "$ASKER"
note "quick ask: $ASKER"
install -m 755 "$ROOT/tools/frieren-shot.sh" "$SHOT"
note "screenshot: $SHOT"
install -m 755 "$ROOT/tools/frieren-backup.sh" "$BACKUPER"
note "backup: $BACKUPER"
install -m 755 "$ROOT/tools/frieren-weekly.sh" "$WEEKLY"
note "weekly: $WEEKLY"
install -m 755 "$ROOT/tools/frieren-voice.sh" "$VOICER"
note "voices: $VOICER"

for helper in frieren-listen.sh frieren-say.sh; do
  install -m 755 "$ROOT/quickshell/frieren/tools/$helper" \
    "$QS_DIR/tools/$helper"
done
note "voice helpers: $QS_DIR/tools/"

install -m 644 "$ROOT/quickshell/frieren/assets/frieren-icon.png" \
  "$ICON_DIR/frieren.png"

cat > "$APP_DIR/frieren.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Frieren
Comment=Chibi Frieren desktop pet with an opencode chat
Exec=$LAUNCHER
Icon=$ICON_DIR/frieren.png
Terminal=false
Categories=Utility;
Keywords=pet;assistant;opencode;desktop;
StartupNotify=false
EOF
note "menu: $APP_DIR/frieren.desktop"

if [ -e "$OC_DIR/frieren.md" ] && [ "$FORCE" -ne 1 ]; then
  echo "warning: $OC_DIR/frieren.md already exists, not overwriting it (use --force)" >&2
else
  cp "$ROOT/opencode/agents/frieren.md" "$OC_DIR/frieren.md"
  note "agent: $OC_DIR/frieren.md"
fi

refresh_caches

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "note: $BIN is not in PATH; use the app menu or the absolute path." ;;
esac

cat <<'EOF'

Installed. You still need to hook it into the compositor.

DankMaterialShell: add the bind to ~/.config/hypr/dms/binds-user.lua

  hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c frieren ipc call frieren toggle"))

Hyprland with your own config: copy hypr/frieren.lua to ~/.config/hypr/ and add
require("frieren") at the end of hyprland.lua.

To start it automatically on every login, add this to the same file:

  hl.on("hyprland.start", function()
      hl.exec_cmd("qs -c frieren -n")
  end)

Try it now:

  ~/.local/bin/frieren           # app menu entry, or this command
  qs -c frieren ipc call frieren toggle

Fresh install: open the tray icon and choose "Setup account" to add your API
key, or use Terminal login for providers that need a browser.

Chat history and the activity log share ~/.local/state/frieren/frieren.db.
Inspect it with: sqlite3 ~/.local/state/frieren/frieren.db ".tables"

Before using it, check the model in opencode/agents/frieren.md and in
quickshell/frieren/shell.qml (modelName): it must be one your account can pay for.
EOF
