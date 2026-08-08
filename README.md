# Garmin Recovery Widget for macOS

A macOS WidgetKit widget that displays near-real-time Garmin Connect recovery metrics on your desktop.

**Metrics displayed:** Training Readiness, Body Battery, Stress, VO2 Max, HRV, Sleep Score

## Architecture

```
Python Fetcher (every 15 min via launchd)
    → Fetches data from Garmin Connect API
    → Writes JSON to App Group container

macOS Widget Extension (WidgetKit)
    → Reads JSON from App Group container
    → Renders medium-sized widget with 6 metrics
```

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15+
- Python 3.10+ (via Homebrew: `brew install python`)
- A Garmin Connect account with a compatible device

## Setup Instructions

### 1. Install Python Dependencies

```bash
cd fetcher
pip3 install -r requirements.txt
```

### 2. First-Time Garmin Login

Run the interactive login script to authenticate and save tokens:

```bash
cd fetcher
python3 first_login.py
```

This will prompt for your Garmin email, password, and MFA code (if enabled).
Tokens are saved to `~/.garminconnect/` for automatic refresh.

### 3. Install the Background Fetcher

```bash
chmod +x scripts/install-launchd.sh
./scripts/install-launchd.sh
```

This installs a launchd agent that runs the fetcher every 15 minutes.

### 4. Set Up the Xcode Project

Since WidgetKit requires an Xcode project with specific targets, you need to create it manually:

1. **Open Xcode** → File → New → Project → macOS → App
   - Product Name: `GarminWidget`
   - Team: Your Personal Team (free Apple ID)
   - Bundle Identifier: `com.garminwidget.app`
   - Interface: SwiftUI
   - Language: Swift

2. **Add Widget Extension Target:**
   - File → New → Target → macOS → Widget Extension
   - Product Name: `GarminWidgetExtension`
   - Uncheck "Include Configuration App Intent" (we use StaticConfiguration)

3. **Configure App Group:**
   - Select the main app target → Signing & Capabilities → + Capability → App Groups
   - Add: `group.com.garminwidget.shared`
   - Repeat for the widget extension target

4. **Add Source Files:**
   - **Main App target:** Add all files from `GarminWidget/App/` and `GarminWidget/Shared/`
   - **Widget Extension target:** Add all files from `GarminWidget/Widget/` and `GarminWidget/Shared/`
   - Important: `GarminMetrics.swift` (Shared) must belong to BOTH targets

5. **Set Entitlements:**
   - Main app: Use `GarminWidget/App/GarminWidget.entitlements`
   - Widget extension: Use `GarminWidget/Widget/GarminWidgetExtension.entitlements`

6. **Disable App Sandbox** (for development — allows the app to run Python):
   - Main app target → Signing & Capabilities → Remove "App Sandbox" if present

7. **Build & Run** the main app target, then add the widget to your desktop via the widget gallery.

## File Structure

```
garmin-widget/
├── fetcher/
│   ├── garmin_fetcher.py       # Background data fetcher (runs via launchd)
│   ├── first_login.py          # Interactive first-time auth setup
│   └── requirements.txt        # Python dependencies
├── launchd/
│   └── com.garminwidget.fetcher.plist  # Template launchd agent
├── scripts/
│   └── install-launchd.sh      # Installer for the launchd agent
├── GarminWidget/
│   ├── Shared/
│   │   └── GarminMetrics.swift         # Data model (shared between targets)
│   ├── App/
│   │   ├── GarminWidgetApp.swift       # App entry point
│   │   ├── ContentView.swift           # Settings/status UI
│   │   ├── AppViewModel.swift          # App logic/state
│   │   └── GarminWidget.entitlements   # App entitlements
│   └── Widget/
│       ├── GarminWidgetBundle.swift     # Widget bundle entry point
│       ├── GarminWidgetProvider.swift   # Timeline provider
│       ├── GarminWidgetView.swift       # Widget SwiftUI view
│       └── GarminWidgetExtension.entitlements
└── README.md
```

## Troubleshooting

- **Widget shows "--" for all values:** The fetcher hasn't run yet or can't authenticate. Check `/tmp/garmin-widget-fetcher.stdout.log`.
- **"Not Connected" in host app:** Run `first_login.py` to set up authentication.
- **Token expired:** Tokens auto-refresh, but if your refresh token is revoked (e.g., password change), re-run `first_login.py`.
- **Widget not updating:** WidgetKit has a budget of 40-70 refreshes/day. Ensure the launchd agent is running: `launchctl list | grep garminwidget`.

## Notes

- This uses the unofficial `python-garminconnect` library. Garmin may change their API without notice.
- Credentials are stored locally in `~/Library/Group Containers/group.com.garminwidget.shared/config.json` with restricted permissions (0600).
- The widget refreshes every ~15 minutes, which is appropriate for recovery metrics that change slowly.
