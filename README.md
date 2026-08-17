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

## Installation

DMG releases are available on the [Releases](https://github.com/terrancehah/Bodily/releases) page.

1. Download the latest `.dmg` file
2. Open it and drag **Bodily** to your Applications folder
3. Launch the app and log in with your Garmin Connect credentials
4. Add the widget to your desktop via the macOS widget gallery

> **Requirements:** macOS 14 (Sonoma) or later, and a Garmin Connect account.

## File Structure

```
Bodily/
├── Bodily/                              # Host app target
│   ├── BodilyApp.swift                   # App entry point
│   ├── ContentView.swift                 # Main UI with customizable metric grid
│   ├── AppViewModel.swift                # App state, drag-and-drop logic
│   ├── GarminMetrics.swift               # Shared data model, styling, metric catalog
│   ├── LoginView.swift                   # Garmin login flow
│   ├── AccountView.swift                 # Account & device info
│   └── Bodily.entitlements               # App Group entitlements
├── BodilyWidget/                        # Widget extension target
│   ├── BodilyWidgetBundle.swift          # Widget bundle entry point
│   ├── BodilyWidgetProvider.swift        # Timeline provider
│   ├── BodilyWidgetView.swift            # Widget tile grid view
│   ├── Info.plist
│   └── Assets.xcassets/                  # Widget assets
├── BodilyWidget.entitlements            # Widget App Group entitlements
├── Bodily.xcodeproj/                    # Xcode project
├── fetcher/                             # Python background fetcher
│   ├── garmin_fetcher.py                 # Main metric fetcher
│   ├── first_login.py                    # Interactive first-time auth
│   ├── login.py                          # Login & token refresh
│   ├── account-info.py                   # Profile & device info fetcher
│   ├── debug_fetch.py                    # Debug utility
│   └── requirements.txt                  # Python dependencies
├── launchd/
│   └── com.bodily.fetcher.plist          # LaunchAgent template
├── scripts/
│   ├── install-launchd.sh                # LaunchAgent installer
│   ├── copy-fetcher-to-resources.sh      # Xcode build phase script
│   └── create-dmg.sh                     # DMG packaging script
├── .gitignore
├── LICENSE
└── README.md
```

## License

MIT — see [LICENSE](LICENSE).

## Notes

- This uses the unofficial `python-garminconnect` library. Garmin may change their API without notice.
- Credentials are stored locally in `~/.garminconnect/` with restricted permissions; the Garmin password is stored in the macOS Keychain.
- The widget refreshes every ~15 minutes, which is appropriate for recovery metrics that change slowly.
- The companion app uses a cooldown-based drag-and-drop mechanism to prevent card jumping during reordering.
- Auto-updates are powered by [Sparkle](https://sparkle-project.org/). To enable EdDSA-signed updates:
    1. Generate keys: `openssl genpkey -algorithm ed25519 -out sparkle_private.pem`
    2. Add the private key as a GitHub Actions secret named `SPARKLE_PRIVATE_KEY`
    3. The CI workflow will sign each release automatically
