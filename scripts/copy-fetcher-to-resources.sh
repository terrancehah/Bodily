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
# ============================================================

set -e

SRC_DIR="${PROJECT_DIR}/fetcher"
DST_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/fetcher"

echo "Copying fetcher scripts to app bundle..."
echo "  Source: ${SRC_DIR}"
echo "  Dest:   ${DST_DIR}"

# Create destination directory
mkdir -p "${DST_DIR}"

# Copy only Python source files (skip __pycache__, config, credentials, generated JSON)
for file in "${SRC_DIR}"/*.py "${SRC_DIR}"/requirements.txt; do
    if [ -f "$file" ]; then
        cp "$file" "${DST_DIR}/"
        echo "  → $(basename "$file")"
    fi
done

echo "Fetcher scripts copied successfully."
