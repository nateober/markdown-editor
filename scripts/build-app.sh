#!/bin/bash
set -euo pipefail

# MarkdownEditor - Build .app bundle
# Usage: ./scripts/build-app.sh [--sign] [--notarize]

SIGN=false
NOTARIZE=false
DEVELOPER_ID="Developer ID Application: Nate Ober (684GQ6L3D9)"
TEAM_ID="684GQ6L3D9"
BUNDLE_ID="com.nateober.MarkdownEditor"

for arg in "$@"; do
    case $arg in
        --sign) SIGN=true ;;
        --notarize) NOTARIZE=true; SIGN=true ;;
    esac
done

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/release"
APP_DIR="$PROJECT_DIR/build/MarkdownEditor.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

echo "==> Creating .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BUILD_DIR/MarkdownEditor" "$MACOS/MarkdownEditor"

# Copy Info.plist
cp "$PROJECT_DIR/MarkdownEditor/App/Info.plist" "$CONTENTS/Info.plist"

# Copy resource bundle into Contents/Resources/
cp -R "$BUILD_DIR/MarkdownEditor_MarkdownEditor.bundle" "$RESOURCES/"

# Copy app icon if it exists
if [ -f "$PROJECT_DIR/MarkdownEditor/App/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/MarkdownEditor/App/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

echo "==> App bundle created at: $APP_DIR"

if [ "$SIGN" = true ]; then
    echo "==> Signing app bundle..."
    codesign --force --deep --options runtime \
        --sign "$DEVELOPER_ID" \
        --entitlements "$PROJECT_DIR/MarkdownEditor/App/MarkdownEditor.entitlements" \
        "$APP_DIR"
    echo "==> Verifying signature..."
    codesign --verify --verbose "$APP_DIR"
    spctl --assess --type execute --verbose "$APP_DIR" 2>&1 || true
fi

if [ "$NOTARIZE" = true ]; then
    echo "==> Creating ZIP for notarization..."
    ZIP_PATH="$PROJECT_DIR/build/MarkdownEditor.zip"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$ZIP_PATH" \
        --team-id "$TEAM_ID" \
        --keychain-profile "notarytool" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$APP_DIR"

    rm -f "$ZIP_PATH"
    echo "==> Notarization complete!"
fi

echo ""
echo "Done! App is at: $APP_DIR"
echo "To install: cp -R build/MarkdownEditor.app /Applications/"
