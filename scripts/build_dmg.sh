#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/VideoEasyTool.app"
DMG="$DIST/VideoEasyTool.dmg"
RW_DMG="$DIST/VideoEasyTool-rw.dmg"
STAGE_DIR="/tmp/VideoEasyTool-dmg"
MOUNT_DIR="/Volumes/Video Easy Tool"
BG_DIR="$STAGE_DIR/.background"
BG_FILE="$BG_DIR/background.png"

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found at $APP" >&2
  exit 1
fi

swift "$ROOT/scripts/make_dmg_background.swift"

rm -rf "$STAGE_DIR" "$RW_DMG" "$DMG"
mkdir -p "$BG_DIR"
cp -R "$APP" "$STAGE_DIR/"
cp "$ROOT/assets/dmg-background.png" "$BG_FILE"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create -quiet -volname "Video Easy Tool" -srcfolder "$STAGE_DIR" -ov -format UDRW "$RW_DMG"

MOUNT_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
ATTACH_LINE="$(echo "$MOUNT_OUTPUT" | grep '/Volumes/' | tail -n 1)"
DEVICE="$(echo "$ATTACH_LINE" | awk '{print $1}')"
MOUNT_DIR="$(echo "$ATTACH_LINE" | sed -E 's#^.*(/Volumes/.*)$#\1#')"

if [[ -z "$DEVICE" || -z "$MOUNT_DIR" ]]; then
  echo "Failed to mount temporary DMG" >&2
  exit 1
fi

VOLUME_NAME="$(basename "$MOUNT_DIR")"

cleanup() {
  hdiutil detach "$DEVICE" -quiet || true
}
trap cleanup EXIT

osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {160, 120, 880, 560}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 152
        set text size of theViewOptions to 14
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "VideoEasyTool.app" of container window to {170, 250}
        set position of item "Applications" of container window to {550, 250}
        update without registering applications
        delay 1
        close
        open
        delay 1
    end tell
end tell
EOF

SetFile -a V "$MOUNT_DIR/.background"
SetFile -a V "$MOUNT_DIR/.fseventsd" 2>/dev/null || true

hdiutil detach "$DEVICE" -quiet
trap - EXIT

hdiutil convert "$RW_DMG" -quiet -format UDZO -o "$DMG"
rm -f "$RW_DMG"
echo "Created $DMG"
