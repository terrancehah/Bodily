import SwiftUI
import Sparkle

/// Main entry point for the Bodily host application.
/// Provides a minimal dashboard for daily metrics and fetcher controls.
@main
struct BodilyApp: App {
    /// Sparkle auto-update controller — adds "Check for Updates..." to the app menu.
    /// Update checks are deferred until after login to avoid errors on first launch
    /// (the DMG from GitHub is already the latest version).
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Defer update checks until the user has logged in and data is flowing.
        // On first launch with an empty or missing appcast, Sparkle would show
        // a confusing error dialog. We enable checks later via enableUpdateChecks().
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
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
