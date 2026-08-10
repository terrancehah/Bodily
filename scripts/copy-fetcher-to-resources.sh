#!/bin/bash
# ============================================================
# Xcode Build Phase: Copy Fetcher Scripts into App Resources
#
# Copies the Python fetcher scripts into the built .app bundle's
# Resources/fetcher/ directory so the app can run them at runtime
# without relying on the Xcode project directory.
#
# Add this as a "Run Script" build phase in Xcode:
#   Target: Bodily (the main app, NOT the widget extension)
#   Position: After "Copy Bundle Resources"
#   Shell: /bin/bash
#   Script: "${PROJECT_DIR}/scripts/copy-fetcher-to-resources.sh"
#   Input Files: (none)
#   Output Files:
#     ${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/fetcher/garmin_fetcher.py
# ============================================================

SRC_DIR="${PROJECT_DIR}/fetcher"
DST_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/fetcher"
MARKER="${DST_DIR}/.copied"

echo "Copying fetcher scripts to app bundle..."
echo "  Source: ${SRC_DIR}"
echo "  Dest:   ${DST_DIR}"

# Skip if source hasn't changed since last copy
if [ -f "${MARKER}" ] && [ "$(find "${SRC_DIR}" -name '*.py' -newer "${MARKER}" 2>/dev/null)" = "" ]; then
    echo "  → Skipped (no changes since last copy)"
    exit 0
fi

# Create destination directory
mkdir -p "${DST_DIR}"

# Copy Python source files (skip __pycache__, config, credentials, generated JSON)
copied=0
for file in "${SRC_DIR}"/*.py "${SRC_DIR}"/requirements.txt; do
    if [ -f "$file" ]; then
        cp "$file" "${DST_DIR}/"
        echo "  → $(basename "$file")"
        copied=1
    fi
done

if [ $copied -eq 0 ]; then
    echo "  WARNING: No fetcher scripts found at ${SRC_DIR}"
fi

# Touch marker for incremental build support
touch "${MARKER}"
echo "Fetcher scripts copied successfully."
