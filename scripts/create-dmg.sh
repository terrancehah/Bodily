#!/bin/bash
# ============================================================
# Bodily DMG Creator
#
# Archives the app in Release configuration, then packages it
# into a .dmg with a symlink to /Applications.
#
# Usage:
#   ./scripts/create-dmg.sh
#
# Environment variables (optional, for CI version injection):
#   MARKETING_VERSION      e.g. "1.0.0" — overrides CFBundleShortVersionString
#   CURRENT_PROJECT_VERSION e.g. "4"    — overrides CFBundleVersion
#
# Prerequisites:
#   - Xcode with the Bodily project open (or scheme built once)
#   - The "Copy Fetcher Scripts" build phase must be added
#
# Output:
#   build/Bodily-<version>.dmg  (or build/Bodily.dmg if no version set)
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_NAME="Bodily"

# Version-aware DMG filename: Bodily-1.0.0.dmg when MARKETING_VERSION is set
VERSION_SUFFIX="${MARKETING_VERSION:+-${MARKETING_VERSION}}"
DMG_NAME="${APP_NAME}${VERSION_SUFFIX}.dmg"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

echo "=== Bodily DMG Creator ==="
echo

# Step 1: Clean build directory
echo "1. Cleaning build directory..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Step 2: Archive the app in Release configuration.
# Build version overrides from environment (used by CI to inject git tag version).
echo "2. Archiving ${APP_NAME} (Release)..."
XCODEBUILD_VERSION_FLAGS=()
if [ -n "${MARKETING_VERSION}" ]; then
    XCODEBUILD_VERSION_FLAGS+=("MARKETING_VERSION=${MARKETING_VERSION}")
    echo "   Version override: MARKETING_VERSION=${MARKETING_VERSION}"
fi
if [ -n "${CURRENT_PROJECT_VERSION}" ]; then
    XCODEBUILD_VERSION_FLAGS+=("CURRENT_PROJECT_VERSION=${CURRENT_PROJECT_VERSION}")
    echo "   Build override: CURRENT_PROJECT_VERSION=${CURRENT_PROJECT_VERSION}"
fi

xcodebuild archive \
    -project "${PROJECT_DIR}/Bodily.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    "${XCODEBUILD_VERSION_FLAGS[@]}" \
    | grep -v "^note:" | grep -v "^warning:" || true

echo "   Archive created at: ${ARCHIVE_PATH}"

# Step 3: Export the .app from the archive
echo "3. Exporting .app from archive..."

# Create a minimal exportOptions.plist
EXPORT_OPTIONS="${BUILD_DIR}/exportOptions.plist"
cat > "${EXPORT_OPTIONS}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string></string>
</dict>
</plist>
EOF

# Copy the .app directly from the archive (simpler than export for unsigned builds)
cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${APP_PATH}"

echo "   App copied to: ${APP_PATH}"

# Step 4: Create the DMG
echo "4. Creating DMG..."

# Create a temporary directory for DMG contents
DMG_TMP="${BUILD_DIR}/dmg_tmp"
rm -rf "${DMG_TMP}"
mkdir -p "${DMG_TMP}"

# Copy the app
cp -R "${APP_PATH}" "${DMG_TMP}/"

# Create a symlink to /Applications
ln -s /Applications "${DMG_TMP}/Applications"

# Create the DMG
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_TMP}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

# Clean up temp directory
rm -rf "${DMG_TMP}"

echo
echo "=== Done ==="
echo "DMG created at: ${DMG_PATH}"
echo
echo "To distribute:"
echo "  1. Test the DMG by opening it and dragging the app to /Applications"
echo "  2. For signed distribution, add your Developer ID certificate and run:"
echo "     codesign --deep --force --verify --verbose --sign \"Developer ID Application: Your Name\" ${APP_PATH}"
echo "     hdiutil create ... (re-run step 4 after signing)"
echo "     xcrun notarytool submit ${DMG_PATH} --apple-id your@email.com --team-id XXXXXX --wait"
echo "     xcrun stapler staple ${DMG_PATH}"
