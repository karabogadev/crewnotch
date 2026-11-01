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

# Sign with Developer ID when one is installed; otherwise fall back to an
# ad-hoc signature (the app then has to be allowed once in Privacy & Security).
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    SIGNING=developer-id
else
    SIGNING=adhoc
    echo "No Developer ID certificate found: building an ad-hoc signed app."
fi

pretty() { if command -v xcpretty &>/dev/null; then xcpretty; else cat; fi; }

echo "Archiving..."
set +e
if [ "$SIGNING" = developer-id ]; then
    xcodebuild archive -scheme CrewNotch -configuration Release -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_STYLE=Automatic 2>&1 | pretty
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

EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

echo ""
echo "Exporting..."
set +e
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" 2>&1 | pretty
EXPORT_EXIT=${PIPESTATUS[0]}
set -e
if [ "$EXPORT_EXIT" -ne 0 ]; then
    echo "ERROR: Export failed."
    exit 1
fi

echo ""
echo "=== Build Complete ==="
echo "App exported to: $EXPORT_PATH/CrewNotch.app"
echo ""
echo "Next: Run ./scripts/create-release.sh to notarize and create DMG"
