#!/bin/bash
# Installs the latest MacPad release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/jadhavgaurav/MacPad/main/install.sh | bash
#
# The script downloads the release disk image, checks it against the published SHA-256 checksum,
# copies MacPad.app into /Applications and opens it. It does not change any macOS security setting.
set -euo pipefail

REPO="jadhavgaurav/MacPad"
APP="/Applications/MacPad.app"

echo "==> Looking up the latest release"
URLS="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep -o 'https://[^"]*macos\.dmg\(\.sha256\)\?')"
URL="$(printf '%s\n' "$URLS" | grep -v '\.sha256$' | head -1)"
SUM_URL="$(printf '%s\n' "$URLS" | grep '\.sha256$' | head -1 || true)"
if [ -z "$URL" ]; then
  echo "Could not find a .dmg in the latest release of $REPO" >&2
  exit 1
fi

TMP="$(mktemp -d)"
MOUNT=""
cleanup() {
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

NAME="$(basename "$URL")"
echo "==> Downloading $NAME"
curl -fL --progress-bar "$URL" -o "$TMP/$NAME"

if [ -n "$SUM_URL" ]; then
  echo "==> Verifying the checksum"
  EXPECTED="$(curl -fsSL "$SUM_URL" | awk '{print $1}')"
  ACTUAL="$(shasum -a 256 "$TMP/$NAME" | awk '{print $1}')"
  if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Checksum mismatch: expected $EXPECTED but got $ACTUAL" >&2
    exit 1
  fi
fi

echo "==> Mounting the disk image"
MOUNT="$(hdiutil attach "$TMP/$NAME" -nobrowse -readonly | tail -1 | sed 's/.*\(\/Volumes\/.*\)/\1/')"
if [ ! -d "$MOUNT/MacPad.app" ]; then
  echo "That disk image does not contain MacPad.app" >&2
  exit 1
fi

if pgrep -x MacPad >/dev/null 2>&1; then
  echo "==> Quitting the running copy"
  osascript -e 'tell application "MacPad" to quit' >/dev/null 2>&1 || true
  sleep 1
fi

echo "==> Installing to $APP"
rm -rf "$APP"
cp -R "$MOUNT/MacPad.app" "$APP"

open "$APP"
echo
echo "MacPad is installed and running."
