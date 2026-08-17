#!/bin/bash
# ============================================================
# Bodily Fetcher - launchd Agent Installer (DEPRECATED)
#
# This script is no longer needed for end users.
# The Bodily app automatically sets up the launchd agent and
# Python virtual environment on first launch — no manual steps
# required. Just open the app and log in.
#
# This script remains as documentation of the underlying
# launchd setup for developers working on the project.
# ============================================================

echo "========================================"
echo " Bodily Fetcher Installer — DEPRECATED"
echo "========================================"
echo
echo "This script is no longer needed."
echo "The Bodily app handles everything automatically:"
echo "  - Creates a Python virtual environment"
echo "  - Installs the garminconnect package"
echo "  - Sets up the launchd agent to fetch every 15 min"
echo
echo "Just open the Bodily app and log in with your"
echo "Garmin Connect account."
echo
echo "To force a reinstall of the launchd agent from the"
echo "app, delete this file and restart Bodily:"
echo "  ~/Library/LaunchAgents/com.bodily.fetcher.plist"
echo

exit 0
