import SwiftUI
import Sparkle

/// Main entry point for the Bodily host application.
/// Provides a minimal dashboard for daily metrics and fetcher controls.
@main
struct BodilyApp: App {
    /// Sparkle auto-update controller — adds "Check for Updates..." to the app menu
    /// and checks for new DMG releases on GitHub periodically.
    /// Feed URL is set before initialization so Sparkle picks it up on first launch.
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Sparkle reads SUFeedURL from UserDefaults before falling back to Info.plist.
        // Setting it here ensures the updater knows where to find the appcast on first launch.
        let feedURL = "https://raw.githubusercontent.com/terrancehah/Bodily/main/appcast.xml"
        UserDefaults.standard.set(feedURL, forKey: "SUFeedURL")

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 400)
    }
}
