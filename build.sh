#!/bin/bash
# build.sh — Build FileShift macOS app bundle
set -e

echo "🔨 Building FileShift..."

# Build the Swift executable
swift build -c release 2>&1

# Create .app bundle structure
APP_DIR=".build/FileShift.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp .build/release/FileShift "$MACOS_DIR/"

# Copy Info.plist
cp Info.plist "$CONTENTS_DIR/"

# Copy AppIcon
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$RESOURCES_DIR/"
fi

# Ad-hoc code signing (required for macOS Gatekeeper and arm64 execution)
echo "🔏 Ad-hoc code signing FileShift.app..."
codesign --force --deep --sign - "$APP_DIR"

echo "✅ Built: $APP_DIR"
echo ""
echo "To run: open $APP_DIR"
echo "Or:     .build/release/FileShift"
