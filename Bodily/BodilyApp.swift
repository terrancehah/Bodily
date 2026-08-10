import SwiftUI

/// Main entry point for the Bodily host application.
/// Provides a minimal dashboard for daily metrics and fetcher controls.
@main
struct BodilyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 400)
    }
}
