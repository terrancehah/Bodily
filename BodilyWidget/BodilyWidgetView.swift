import WidgetKit
import SwiftUI

/// The main widget definition for Bodily daily metrics.
/// Supports medium (6 tiles, 3×2) and large (9 tiles, 3×3) families.
struct BodilyWidget: Widget {
    let kind: String = "BodilyWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BodilyMetricsProvider()) { entry in
            BodilyWidgetView(entry: entry)
                // Slate-tinted surface: off-white in light mode, near-black in dark mode
                .containerBackground(BodilyPalette.surface, for: .widget)
        }
        .configurationDisplayName("Bodily")
        .description("Your Garmin metrics at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

/// The SwiftUI view rendered inside the widget.
/// Medium: 6 metrics in a 3×2 grid. Large: 9 metrics in a 3×3 grid.
struct BodilyWidgetView: View {
    let entry: BodilyMetricsEntry
    @Environment(\.widgetFamily) var family
    
    /// Number of tiles to show based on the widget family
    private var tileCount: Int {
        switch family {
        case .systemLarge: return 9
        default: return 6
        }
    }
    
    /// Vertical spacing between grid rows — tighter for medium, roomier for large
    private var rowSpacing: CGFloat {
        family == .systemLarge ? 16 : 8
    }
    
    var body: some View {
        // Tiles follow the host app's customized selection (order included),
        // read from the shared App Group suite and capped at the family's capacity
        let selection = MetricID.savedSelection(maxCount: tileCount)

        VStack(spacing: 0) {
            // Header: tracked wordmark on the left, timestamp on the right
            HStack(alignment: .center, spacing: 5) {
                Text("BODILY")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(BodilyPalette.secondaryText)

                Spacer()

                // Formatted timestamp like "Last updated: Today 13:35"
                Text(formattedTimestamp)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(BodilyPalette.tertiaryText)
            }
            .padding(.bottom, 4)

            // Center the grid vertically in the remaining space
            Spacer(minLength: 0)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                spacing: rowSpacing
            ) {
                ForEach(selection) { metricID in
                    MetricTile(
                        label: metricID.title,
                        metric: metricID.entry(from: entry.metrics),
                        icon: metricID.icon,
                        type: metricID.type,
                        format: metricID.format,
                        unit: metricID.unit
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .padding(16)
    }
    
    // MARK: - Timestamp Formatting

    /// Fetch timestamp string ("Last updated: Today 13:35") — formatting lives in the
    /// shared GarminMetrics extension so the widget and host app read identically.
    private var formattedTimestamp: String {
        entry.metrics.formattedLastUpdated
    }
}


/// A single metric tile: icon + bold zone-colored value, tracked small-caps label,
/// and the signature gauge bar showing where the value sits in its scale.
/// Top-zone metrics earn the green accent; everything else uses the Garmin zone color.
struct MetricTile: View {
    let label: String
    let metric: MetricEntry
    let icon: String
    let type: MetricType
    var format: String = "%.0f"
    var unit: String = ""

    /// Gauge fill fraction — for text metrics like Training Status, derived from the level.
    private var gaugeFraction: Double? {
        if let value = metric.value {
            return MetricStyling.gaugeFraction(type: type, value: value, level: metric.level, goal: metric.goal)
        } else if metric.level != nil {
            return MetricStyling.gaugeFraction(type: type, value: 0, level: metric.level)
        }
        return nil
    }

    /// Gauge fill color — for text metrics, uses the zone color of the level.
    private var gaugeFillColor: Color? {
        if let value = metric.value {
            return MetricStyling.gaugeColor(type: type, value: value, level: metric.level, goal: metric.goal)
        } else if let level = metric.level {
            return MetricStyling.zoneColor(type: type, value: 0, level: level)
        }
        return nil
    }
    
    /// body for the metric tiles/cards.
    var body: some View {
        VStack(spacing: 0) {
            // Section 1: Readings + Details — flexible height,
            // the value row always starts at the same position across tiles
            VStack(alignment: .center, spacing: 0) {
                // Icon + color-coded value row — the value is the hero
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BodilyPalette.secondaryText)

                    if let value = metric.value {
                        Text(MetricStyling.formattedValue(value, format: format) + unit)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(MetricStyling.zoneColor(type: type, value: value, level: metric.level, goal: metric.goal))
                    } else if let level = metric.level {
                        // Text metric (e.g. Training Status): the level word is the hero
                        Text(level.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(MetricStyling.zoneColor(type: type, value: 0, level: level))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        // No data available — show blank placeholder
                        Text("--")
                            .font(.system(size: 22, weight: .regular, design: .rounded))
                            .foregroundStyle(BodilyPalette.tertiaryText)
                    }
                }

                // Secondary detail line: sleep duration or training load status.
                // Collapses to zero height when absent — no reserved space.
                if let detail = metric.detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(BodilyPalette.tertiaryText)
                        .lineLimit(1)
                } else if let value = metric.value, let level = metric.level {
                    // Metrics with both a numeric value and a level (e.g. Training Readiness, Training Load)
                    Text(level.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(MetricStyling.zoneColor(type: type, value: value, level: level))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Section 2: GaugeBar — always present so every tile has the same
            // structural rhythm. Text metrics like Training Status get a fill
            // derived from their status level.
            GaugeBar(fraction: gaugeFraction, fillColor: gaugeFillColor)
                .padding(.top, 5)

            // Section 3: Title — pinned to the bottom so labels align across
            // every tile in a row regardless of detail-line presence
            HStack(spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(BodilyPalette.secondaryText)
                    .lineLimit(1)

                // Show source date if data is not from today
                if let updatedLabel = metric.lastUpdatedLabel {
                    Text("· \(updatedLabel)")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(BodilyPalette.tertiaryText)
                }
            }
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


// Widget previews on macOS use the WidgetKit Simulator, not Xcode Canvas.
// To preview: select the "BodilyWidget" scheme, then Product > Run (⌘R).
// This launches the WidgetKit Simulator with the configured family and timeline.
