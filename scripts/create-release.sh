#!/bin/bash
# Package the exported app as a DMG (notarized when Developer ID signed)
# and publish a GitHub release. SKIP_PUBLISH=1 stops after the DMG.
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

# Notarize only when the app is Developer ID signed and credentials exist
NOTARIZE=no
if codesign -dv "$APP_PATH" 2>&1 | grep -q "Authority=Developer ID Application"; then
    if xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null; then
        NOTARIZE=yes
    else
        echo "No notarization credentials. Store them once with:"
        echo "  xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" --apple-id <you@example.com> --team-id $TEAM_ID --password <app-specific-password>"
        exit 1
    fi
else
    echo "Ad-hoc signed build: skipping notarization."
fi

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$2"
}

if [ "$NOTARIZE" = yes ]; then
    echo "--- Notarizing app"
    ZIP_PATH="$BUILD_DIR/CrewNotch-$VERSION.zip"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    notarize "$ZIP_PATH" "$APP_PATH"
    rm "$ZIP_PATH"
fi

echo "--- Creating DMG"
rm -f "$DMG_PATH"
STAGING="$BUILD_DIR/dmg"
rm -rf "$STAGING" && mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/CrewNotch.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "CrewNotch" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING"

if [ "$NOTARIZE" = yes ]; then
    echo "--- Notarizing DMG"
    notarize "$DMG_PATH" "$DMG_PATH"
fi

if [ "${SKIP_PUBLISH:-0}" = 1 ]; then
    echo "DMG ready: $DMG_PATH (not published)"
    exit 0
fi

NOTES_ARGS=(--generate-notes)
if [ -f "$PROJECT_DIR/releases/notes-$VERSION.md" ]; then
    NOTES_ARGS=(--notes-file "$PROJECT_DIR/releases/notes-$VERSION.md")
fi

echo "--- Publishing GitHub release"
# A version-less copy keeps releases/latest/download/CrewNotch.dmg stable
cp "$DMG_PATH" "$BUILD_DIR/CrewNotch.dmg"
gh release create "v$VERSION" "$DMG_PATH" "$BUILD_DIR/CrewNotch.dmg" --repo "$GITHUB_REPO" \
    --title "CrewNotch v$VERSION" "${NOTES_ARGS[@]}"

echo "Done: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
