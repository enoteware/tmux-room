#!/usr/bin/env bash
set -eo pipefail

REPO="${TMUX_ROOM_REPO:-enoteware/tmux-room}"
REF="${TMUX_ROOM_REF:-main}"
INSTALL_DIR="${TMUX_ROOM_INSTALL_DIR:-$HOME/bin}"
URL="https://raw.githubusercontent.com/$REPO/$REF/bin/tmux-room"
TARGET="$INSTALL_DIR/tmux-room"

mkdir -p "$INSTALL_DIR"
tmp=$(mktemp "$INSTALL_DIR/.tmux-room.install.XXXXXX")
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$URL" -o "$tmp"
bash -n "$tmp"
grep -q '^TMUX_ROOM_VERSION=' "$tmp"
chmod 755 "$tmp"
mv -f "$tmp" "$TARGET"
tmp=""
trap - EXIT

echo "Installed $($TARGET --version) at $TARGET"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    echo
    echo "Add this directory to your PATH:"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    ;;
esac
