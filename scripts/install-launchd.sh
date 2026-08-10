#!/bin/bash
# ============================================================
# Bodily Fetcher - launchd Agent Installer
# Installs the background fetcher that runs every 15 minutes.
# ============================================================

set -e

PLIST_NAME="com.bodily.fetcher.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FETCHER_PATH="$SCRIPT_DIR/fetcher/garmin_fetcher.py"
PLIST_SOURCE="$SCRIPT_DIR/launchd/$PLIST_NAME"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME"

echo "=== Bodily Fetcher Installer ==="
echo

# Verify the fetcher script exists
if [ ! -f "$FETCHER_PATH" ]; then
    echo "ERROR: Fetcher script not found at: $FETCHER_PATH"
    exit 1
fi

# Use the project's virtual environment Python (Homebrew blocks global pip installs)
PYTHON_PATH="$SCRIPT_DIR/.venv/bin/python3"
if [ ! -f "$PYTHON_PATH" ]; then
    echo "ERROR: Virtual environment not found at $SCRIPT_DIR/.venv"
    echo "  Create it with: python3 -m venv .venv && source .venv/bin/activate && pip install garminconnect"
    exit 1
fi

# Verify garminconnect is installed in the venv
if ! "$PYTHON_PATH" -c "import garminconnect" 2>/dev/null; then
    echo "ERROR: garminconnect package not found in venv."
    echo "  Install it with: source .venv/bin/activate && pip install garminconnect"
    exit 1
fi

echo "Using Python at: $PYTHON_PATH"
echo "Fetcher script: $FETCHER_PATH"
echo

# Generate the plist with resolved paths (no shell variable expansion in launchd)
cat > "$PLIST_DEST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.bodily.fetcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON_PATH</string>
        <string>$FETCHER_PATH</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/bodily-fetcher.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/bodily-fetcher.stderr.log</string>
</dict>
</plist>
EOF

echo "Plist written to: $PLIST_DEST"

# Unload existing agent if present (ignore errors if not loaded)
launchctl unload "$PLIST_DEST" 2>/dev/null || true

# Load the new agent
launchctl load "$PLIST_DEST"

echo
echo "✓ launchd agent installed and started!"
echo "  The fetcher will now run every 15 minutes."
echo
echo "  To check status:  launchctl list | grep bodily"
echo "  To view logs:     cat /tmp/bodily-fetcher.stdout.log"
echo "  To uninstall:     launchctl unload $PLIST_DEST && rm $PLIST_DEST"
