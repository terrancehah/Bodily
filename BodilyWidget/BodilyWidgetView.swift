import WidgetKit
import SwiftUI

/// The main widget definition for medium-sized Garmin daily metrics.
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
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

/// The SwiftUI view rendered inside the medium widget.
/// Displays 6 metrics in a 3x2 grid with color-coded values.
struct BodilyWidgetView: View {
    let entry: BodilyMetricsEntry
    
    var body: some View {
        // Tiles follow the host app's customized selection (order included),
        // read from the shared App Group suite and capped at 6
        let selection = MetricID.savedSelection()

        ZStack(alignment: .topLeading) {

            // Header: volt dot + tracked wordmark on the left, timestamp on the right
            HStack(alignment: .center, spacing: 5) {
                // Volt dot — the brand's accent mark, signals the instrument is live
//                Circle()
//                    .fill(BodilyPalette.voltAccent)
//                    .frame(width: 5, height: 5)

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
            .frame(alignment: .top)
            .padding(.bottom, 2)

            // Centered metric grid — 3 columns, as many rows as the selection needs
            VStack(alignment: .center, spacing: 8) {

                Spacer()

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 8
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
            }
            .frame(alignment: .center)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
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
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(MetricStyling.zoneColor(type: type, value: 0, level: level))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    // No data available — show blank placeholder
                    Text("--")
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .foregroundStyle(BodilyPalette.tertiaryText)
                }
            }

            // Secondary detail line: sleep duration or training load status
            if let detail = metric.detail {
                Text(detail)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(BodilyPalette.tertiaryText)
                    .lineLimit(1)
            } else if metric.value != nil, let level = metric.level {
                // Metrics with both a numeric value and a level (e.g. Training Load)
                Text(level.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(MetricStyling.zoneColor(type: type, value: 0, level: level))
                    .lineLimit(1)
            }

            // Gauge: slate track with a zone-colored fill; green when the metric is excellent
            GaugeBar(
                fraction: metric.value.map { MetricStyling.gaugeFraction(type: type, value: $0, goal: metric.goal) },
                fillColor: metric.value.map { MetricStyling.gaugeColor(type: type, value: $0, level: metric.level, goal: metric.goal) }
            )

            // Metric label in tracked small-caps + optional "last updated" date
            HStack(spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(BodilyPalette.secondaryText)
                    .lineLimit(1)
//                    .minimumScaleFactor(0.7)

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


// MARK: - Widget Preview

#Preview(as: .systemMedium) {
    BodilyWidget()
} timeline: {
    BodilyMetricsEntry(date: Date(), metrics: .placeholder, isStale: false)
    BodilyMetricsEntry(date: Date(), metrics: .unavailable, isStale: true)
}
