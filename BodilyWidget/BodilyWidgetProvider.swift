import WidgetKit
import SwiftUI

/// Timeline entry containing the metrics data and its display date.
struct BodilyMetricsEntry: TimelineEntry {
    let date: Date
    let metrics: GarminMetrics
    let isStale: Bool  // True if data is older than 30 minutes
}

/// Timeline provider that reads metrics from the shared JSON file.
/// WidgetKit calls this to get data for rendering the widget.
struct BodilyMetricsProvider: TimelineProvider {
    
    /// Provides a placeholder entry for the widget gallery preview.
    func placeholder(in context: Context) -> BodilyMetricsEntry {
        BodilyMetricsEntry(
            date: Date(),
            metrics: .placeholder,
            isStale: false
        )
    }
    
    /// Provides a snapshot for quick display (e.g., widget gallery).
    func getSnapshot(in context: Context, completion: @escaping (BodilyMetricsEntry) -> Void) {
        let entry = createEntry()
        completion(entry)
    }
    
    /// Provides a timeline of entries for scheduled updates.
    /// Requests a refresh every 15 minutes to align with the fetcher schedule.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BodilyMetricsEntry>) -> Void) {
        let currentEntry = createEntry()
        
        // Request next timeline update in 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [currentEntry], policy: .after(nextUpdate))
        
        completion(timeline)
    }
    
    /// Creates a timeline entry by reading the latest metrics from disk.
    private func createEntry() -> BodilyMetricsEntry {
        // Debug: log the container URL resolution
        let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: MetricsReader.appGroupID
        )
        print("[WidgetProvider] Container URL: \(containerURL?.path ?? "nil")")
        
        let fileURL = containerURL?.appendingPathComponent("garmin_metrics.json")
        print("[WidgetProvider] File URL: \(fileURL?.path ?? "nil")")
        print("[WidgetProvider] File exists: \(fileURL != nil && FileManager.default.fileExists(atPath: fileURL!.path))")
        
        let metrics = MetricsReader.readLatestMetrics() ?? .unavailable
        print("[WidgetProvider] Metrics loaded: \(metrics.error ?? "nil error"), trainingReadiness value: \(metrics.trainingReadiness.value ?? -1)")
        
        // Determine if data is stale (older than 30 minutes)
        let isStale: Bool
        if let elapsed = MetricsReader.timeSinceLastUpdate() {
            isStale = elapsed > 1800  // 30 minutes in seconds
        } else {
            isStale = true
        }
        
        return BodilyMetricsEntry(
            date: Date(),
            metrics: metrics,
            isStale: isStale
        )
    }
}
