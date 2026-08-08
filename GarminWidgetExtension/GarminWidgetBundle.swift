import WidgetKit
import SwiftUI

/// Widget bundle entry point.
/// Registers all widgets provided by this extension.
@main
struct GarminWidgetBundle: WidgetBundle {
    var body: some Widget {
        BodilyWidget()
    }
}
