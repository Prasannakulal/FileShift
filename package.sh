#!/bin/bash
# package.sh — Package FileShift into a distributable DMG and ZIP
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "📦 Packaging FileShift for distribution..."

# 1. Ensure fresh release build
./build.sh

APP_PATH=".build/FileShift.app"
DMG_NAME="FileShift-1.0.0.dmg"
ZIP_NAME="FileShift-1.0.0.zip"
OUTPUT_DIR="dist"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# 2. Package ZIP
echo "🗜️ Creating ZIP archive..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_DIR/$ZIP_NAME"
echo "  ✅ Created $OUTPUT_DIR/$ZIP_NAME"

# 3. Package DMG with drag-to-Applications layout
echo "💿 Creating DMG installer..."
TEMP_DMG="$OUTPUT_DIR/temp.dmg"

# Clean any existing mount
hdiutil detach "/Volumes/FileShift" -force 2>/dev/null || true
rm -f "$TEMP_DMG" "$OUTPUT_DIR/$DMG_NAME"

# Create temporary read-write HFS+ DMG
hdiutil create -size 30m -fs HFS+ -volname "FileShift" -ov "$TEMP_DMG"
DEVICE=$(hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen | head -n 1 | awk '{print $1}')

# Copy application and create /Applications symlink
cp -R "$APP_PATH" "/Volumes/FileShift/"
codesign --force --deep --sign - "/Volumes/FileShift/FileShift.app" 2>/dev/null || true
ln -s /Applications "/Volumes/FileShift/Applications"

# Add background image
mkdir -p "/Volumes/FileShift/.background"
if [ -f "dmg_background.png" ]; then
    cp dmg_background.png "/Volumes/FileShift/.background/background.png"
fi

# Set volume icon
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "/Volumes/FileShift/.VolumeIcon.icns"
    SetFile -a C "/Volumes/FileShift" 2>/dev/null || true
    SetFile -a V "/Volumes/FileShift/.VolumeIcon.icns" 2>/dev/null || true
fi

SetFile -a V "/Volumes/FileShift/.background" 2>/dev/null || true

# Configure Finder window presentation via AppleScript
osascript <<EOF
tell application "Finder"
    tell disk "FileShift"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {300, 150, 860, 510}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        if exists file ".background:background.png" then
            set background picture of theViewOptions to file ".background:background.png"
        end if
        set position of item "FileShift.app" of container window to {130, 170}
        set position of item "Applications" of container window to {430, 170}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

sync
sleep 2
hdiutil detach "$DEVICE" -force

# Convert to final compressed DMG
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$OUTPUT_DIR/$DMG_NAME"
rm -f "$TEMP_DMG"
echo "  ✅ Created $OUTPUT_DIR/$DMG_NAME"

echo ""
echo "🎉 Distribution files ready in $(pwd)/$OUTPUT_DIR/:"
ls -lh "$OUTPUT_DIR"
echo ""
echo "👉 You can upload $OUTPUT_DIR/$DMG_NAME to GitHub Releases, Gumroad, or your website!"
