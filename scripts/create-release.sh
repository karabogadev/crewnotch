#!/bin/bash
# Package the exported (notarized) app as a DMG and publish a GitHub release. SKIP_PUBLISH=1 stops after the DMG.
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

# build.sh already notarized and stapled a Developer ID build. The DMG is
# notarized too when notarytool credentials are stored (optional).
if xcrun stapler validate "$APP_PATH" &>/dev/null; then
    echo "App is notarized and stapled."
else
    echo "Warning: the app isn't notarized; macOS will ask users to allow it once."
fi
NOTARIZE_DMG=no
if codesign -dvv "$APP_PATH" 2>&1 | grep -q "Authority=Developer ID Application" \
    && xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null; then
    NOTARIZE_DMG=yes
fi

echo "--- Creating DMG"
rm -f "$DMG_PATH"
STAGING="$BUILD_DIR/dmg"
rm -rf "$STAGING" && mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/CrewNotch.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "CrewNotch" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING"

if [ "$NOTARIZE_DMG" = yes ]; then
    echo "--- Notarizing DMG"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
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
