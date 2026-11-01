#!/bin/bash
# Notarize the exported app, package it as a DMG and publish a GitHub release.
# Run ./scripts/build.sh first.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$PROJECT_DIR/releases"
APP_PATH="$BUILD_DIR/export/CrewNotch.app"
GITHUB_REPO="karabogadev/crewnotch"
TEAM_ID="6Y4KN2T4LL"
KEYCHAIN_PROFILE="CrewNotch"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: $APP_PATH not found. Run ./scripts/build.sh first."
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DMG_PATH="$RELEASE_DIR/CrewNotch-$VERSION.dmg"
mkdir -p "$RELEASE_DIR"
echo "=== CrewNotch v$VERSION ==="

if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null; then
    echo "No notarization credentials. Store them once with:"
    echo "  xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" --apple-id <you@example.com> --team-id $TEAM_ID --password <app-specific-password>"
    exit 1
fi

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$2"
}

echo "--- Notarizing app"
ZIP_PATH="$BUILD_DIR/CrewNotch-$VERSION.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
notarize "$ZIP_PATH" "$APP_PATH"
rm "$ZIP_PATH"

echo "--- Creating DMG"
rm -f "$DMG_PATH"
if command -v create-dmg &>/dev/null; then
    create-dmg --volname "CrewNotch" --window-size 600 400 --icon-size 100 \
        --icon "CrewNotch.app" 150 200 --app-drop-link 450 200 \
        --hide-extension "CrewNotch.app" "$DMG_PATH" "$APP_PATH"
else
    hdiutil create -volname "CrewNotch" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
fi

echo "--- Notarizing DMG"
notarize "$DMG_PATH" "$DMG_PATH"

echo "--- Publishing GitHub release"
gh release create "v$VERSION" "$DMG_PATH" --repo "$GITHUB_REPO" \
    --title "CrewNotch v$VERSION" --generate-notes

echo "Done: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
