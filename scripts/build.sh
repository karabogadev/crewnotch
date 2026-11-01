#!/bin/bash
# Build CrewNotch for release
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/CrewNotch.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

echo "=== Building CrewNotch ==="
echo ""

# Clean previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$PROJECT_DIR"

# Sign with Developer ID (Xcode creates the certificate on first use through
# the account signed in to Xcode). ADHOC=1 builds an ad-hoc signed app instead,
# which users then have to allow once in Privacy & Security.
if [ "${ADHOC:-0}" = 1 ]; then
    SIGNING=adhoc
    echo "Building an ad-hoc signed app (ADHOC=1)."
else
    SIGNING=developer-id
fi

pretty() { if command -v xcpretty &>/dev/null; then xcpretty; else cat; fi; }

echo "Archiving..."
set +e
if [ "$SIGNING" = developer-id ]; then
    xcodebuild archive -scheme CrewNotch -configuration Release -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" -allowProvisioningUpdates \
        ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_STYLE=Automatic 2>&1 | pretty
else
    xcodebuild archive -scheme CrewNotch -configuration Release -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" ENABLE_HARDENED_RUNTIME=YES \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= 2>&1 | pretty
fi
ARCHIVE_EXIT=${PIPESTATUS[0]}
set -e
if [ "$ARCHIVE_EXIT" -ne 0 ]; then
    echo "ERROR: Archive failed."
    exit 1
fi

mkdir -p "$EXPORT_PATH"
if [ "$SIGNING" = adhoc ]; then
    ditto "$ARCHIVE_PATH/Products/Applications/CrewNotch.app" "$EXPORT_PATH/CrewNotch.app"
    codesign --verify --deep --strict "$EXPORT_PATH/CrewNotch.app"
    echo ""
    echo "=== Build Complete (ad-hoc signed) ==="
    echo "App: $EXPORT_PATH/CrewNotch.app"
    echo "Next: ./scripts/create-release.sh"
    exit 0
fi

# Upload to Apple's notary service through the Xcode account, then export the
# notarized, stapled app. No app-specific password needed.
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

echo ""
echo "Uploading for notarization..."
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$BUILD_DIR/upload" \
    -exportOptionsPlist "$EXPORT_OPTIONS" -allowProvisioningUpdates 2>&1 | grep -E "error|EXPORT"; then
    echo "ERROR: Upload failed. Sign in to Xcode with your Developer Program account,"
    echo "or build an ad-hoc signed app with ADHOC=1 ./scripts/build.sh"
    exit 1
fi

echo "Waiting for Apple to notarize..."
for _ in $(seq 1 60); do
    if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" &>/dev/null; then
        break
    fi
    sleep 15
done
if ! xcrun stapler validate "$EXPORT_PATH/CrewNotch.app" &>/dev/null; then
    echo "ERROR: The notarized app didn't come back in time. Check Xcode's Organizer."
    exit 1
fi
spctl -a -t exec "$EXPORT_PATH/CrewNotch.app"

echo ""
echo "=== Build Complete (Developer ID, notarized) ==="
echo "App: $EXPORT_PATH/CrewNotch.app"
echo "Next: ./scripts/create-release.sh"
