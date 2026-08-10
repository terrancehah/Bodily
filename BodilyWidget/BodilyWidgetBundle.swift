import WidgetKit
import SwiftUI

/// Widget bundle entry point.
/// Registers all widgets provided by this extension.
@main
struct BodilyWidgetBundle: WidgetBundle {
    var body: some Widget {
        BodilyWidget()
    }
}
