# Bodily — Garmin Connect Desktop Widget for macOS

A macOS desktop widget and companion app that displays your Garmin Connect daily metrics in a clean, instrument-panel interface. A Python background fetcher pulls data from the Garmin Connect API every 15 minutes, and a SwiftUI WidgetKit extension renders up to 6 customizable metric tiles on your desktop.

## Screenshots

### Desktop Widget

<img src="bodily.png" width="400" alt="Bodily desktop widget showing 6 Garmin metric tiles">

### Companion App

<img src="bodily-app.png" width="420" alt="Bodily companion app with customizable metric grid and drag-and-drop customize panel">

## Metrics

All 12 available metrics can be dragged into the widget grid via the companion app's customize mode:

| Metric             | Description                                             |
| ------------------ | ------------------------------------------------------- |
| Training Readiness | Daily readiness score with level label                  |
| Body Battery       | Current energy level (0–100)                            |
| Stress             | Average stress score (lower is better)                  |
| VO2 Max            | Cardiovascular fitness estimate                         |
| HRV                | Heart rate variability with balance status              |
| Sleep              | Sleep score with duration detail (e.g. "7h 20m")        |
| Fitness Age        | Estimated age based on fitness level                    |
| Training Status    | Productive, peaking, recovery, etc.                     |
| Steps              | Daily steps with dynamic goal gauge                     |
| Resting HR         | Resting heart rate (bpm)                                |
| Intensity Minutes  | Weekly active minutes vs. goal (vigorous counts double) |
| Training Load      | 7-day acute load with ACWR status (optimal/low/high)    |

## Architecture

```
Python Fetcher (every 15 min via launchd)
    → Authenticates with Garmin Connect API
    → Fetches 12 daily metrics + user goals
    → Writes JSON to shared App Group container

macOS Host App (SwiftUI)
    → Reads JSON from App Group container
    → Displays metric cards in a customizable drag-and-drop grid
    → Persists metric selection to UserDefaults (shared suite)

macOS Widget Extension (WidgetKit)
    → Reads the same JSON + selection from App Group
    → Renders a medium-sized widget with 6 metric tiles
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
Bodily/
├── GarminWidget/                        # Host app target
│   ├── GarminWidgetApp.swift             # App entry point
│   ├── ContentView.swift                 # Main UI with customizable metric grid
│   ├── AppViewModel.swift                # App state, drag-and-drop logic
│   ├── GarminMetrics.swift               # Shared data model, styling, metric catalog
│   ├── LoginView.swift                   # Garmin login flow
│   ├── AccountView.swift                 # Account & device info
│   └── GarminWidget.entitlements         # App Group entitlements
├── GarminWidgetExtension/               # Widget extension target
│   ├── GarminWidgetBundle.swift          # Widget bundle entry point
│   ├── GarminWidgetProvider.swift        # Timeline provider
│   ├── GarminWidgetView.swift            # Widget tile grid view
│   ├── Info.plist
│   └── Assets.xcassets/                  # Widget assets
├── GarminWidgetExtension.entitlements    # Widget App Group entitlements
├── GarminWidget.xcodeproj/              # Xcode project
├── fetcher/                             # Python background fetcher
│   ├── garmin_fetcher.py                 # Main metric fetcher
│   ├── first_login.py                    # Interactive first-time auth
│   ├── login.py                          # Login & token refresh
│   ├── account-info.py                   # Profile & device info fetcher
│   ├── debug_fetch.py                    # Debug utility
│   └── requirements.txt                  # Python dependencies
├── launchd/
│   └── com.garminwidget.fetcher.plist    # LaunchAgent template
├── scripts/
│   └── install-launchd.sh                # LaunchAgent installer
├── .gitignore
├── LICENSE
└── README.md
```

## Troubleshooting

- **Widget shows "--" for all values:** The fetcher hasn't run yet or can't authenticate. Check `/tmp/garmin-widget-fetcher.stdout.log`.
- **"Not Connected" in host app:** Run `first_login.py` to set up authentication.
- **Token expired:** Tokens auto-refresh, but if your refresh token is revoked (e.g., password change), re-run `first_login.py`.
- **Widget not updating:** WidgetKit has a budget of 40-70 refreshes/day. Ensure the launchd agent is running: `launchctl list | grep garminwidget`.

## License

MIT — see [LICENSE](LICENSE).

## Notes

- This uses the unofficial `python-garminconnect` library. Garmin may change their API without notice.
- Credentials are stored locally in `~/.garminconnect/` with restricted permissions.
- The widget refreshes every ~15 minutes, which is appropriate for recovery metrics that change slowly.
- The companion app uses a cooldown-based drag-and-drop mechanism to prevent card jumping during reordering.
