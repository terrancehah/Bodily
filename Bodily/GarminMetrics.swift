import Foundation
import SwiftUI
import AppKit

/// Identifies each metric type for color-coding logic.
/// Used by both the widget extension and host app.
enum MetricType {
    case readiness, bodyBattery, stress, vo2Max, hrv, sleep
    case fitnessAge, trainingStatus, stepsToday, restingHR
    case intensityMinutes, trainingLoad
}

// MARK: - Design Tokens

/// Central color palette for the "Bodily" sports-instrument aesthetic.
/// Brand colors: ink #000000, slate #5D737E (the neutral spine), volt #FFE313 (the single accent).
/// Neutrals are always tinted toward slate; volt is used sparingly so it stays powerful.
enum BodilyPalette {

    // MARK: Brand base colors

    /// Volt yellow #FFE313 — the single accent. Used for excellence states and key actions.
    static let volt = Color(red: 1.0, green: 0xE3 / 255, blue: 0x13 / 255)

    /// Slate #5D737E — the neutral spine that all grays are tinted toward.
    static let slate = Color(red: 0x5D / 255, green: 0x73 / 255, blue: 0x7E / 255)

    /// Near-black tinted toward slate — used for text on volt fills and deepest surfaces.
    static let ink = Color(red: 0x06 / 255, green: 0x08 / 255, blue: 0x0A / 255)

    // MARK: Adaptive helpers

    /// Builds a light/dark adaptive color using AppKit's dynamic provider.
    /// Widget extensions and the host app both resolve this against the current appearance.
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }))
    }

    /// Widget/window background: slate-tinted off-white in light mode, slate-tinted near-black in dark.
    static let surface = adaptive(
        light: NSColor(srgbRed: 0xF3 / 255, green: 0xF5 / 255, blue: 0xF6 / 255, alpha: 1),
        dark: NSColor(srgbRed: 0x0C / 255, green: 0x10 / 255, blue: 0x12 / 255, alpha: 1)
    )

    /// Metric card fill: sits one step above the surface in both modes.
    static let cardFill = adaptive(
        light: NSColor(srgbRed: 0xE8 / 255, green: 0xEC / 255, blue: 0xEE / 255, alpha: 1),
        dark: NSColor(srgbRed: 0x16 / 255, green: 0x1B / 255, blue: 0x1F / 255, alpha: 1)
    )

    /// Hairline border color for instrument-panel card outlines.
    static let hairline = slate.opacity(0.35)

    /// Secondary text: full slate in light mode, lightened slate in dark mode.
    static let secondaryText = adaptive(
        light: NSColor(srgbRed: 0x5D / 255, green: 0x73 / 255, blue: 0x7E / 255, alpha: 1),
        dark: NSColor(srgbRed: 0x93 / 255, green: 0xA5 / 255, blue: 0xAE / 255, alpha: 1)
    )

    /// Tertiary text: dimmer slate for timestamps and metadata.
    static let tertiaryText = adaptive(
        light: NSColor(srgbRed: 0x8A / 255, green: 0x99 / 255, blue: 0xA1 / 255, alpha: 1),
        dark: NSColor(srgbRed: 0x55 / 255, green: 0x68 / 255, blue: 0x72 / 255, alpha: 1)
    )

    /// Gauge track: slate at low opacity so the zone-colored fill reads clearly.
    static let gaugeTrack = slate.opacity(0.22)

    /// Volt variant safe for small text/icons: pure volt in dark mode,
    /// amber-shifted in light mode where full volt would fail contrast.
    static let voltAccent = adaptive(
        light: NSColor(srgbRed: 0xA8 / 255, green: 0x86 / 255, blue: 0x00 / 255, alpha: 1),
        dark: NSColor(srgbRed: 0xFF / 255, green: 0xE3 / 255, blue: 0x13 / 255, alpha: 1)
    )
}

// MARK: - Metric Styling

/// Centralized color and gauge logic for all metrics, based on Garmin's official zones.
/// Shared by the widget tiles and the host app cards so both stay in sync.
enum MetricStyling {

    /// Zone color for a metric value, based on Garmin's official thresholds.
    /// `goal` is supplied for goal-relative metrics (steps, intensity minutes,
    /// training load) so zones track the user's own target instead of a constant.
    static func zoneColor(type: MetricType, value: Double, level: String?, goal: Double? = nil) -> Color {
        switch type {
        // Training Readiness: higher = better
        // 80+ Prime, 60-79 Ready, 40-59 Moderate, 20-39 Low, 0-19 Poor
        case .readiness:
            if value >= 80 { return .green }
            if value >= 60 { return .yellow }
            if value >= 40 { return .orange }
            if value >= 20 { return .red.opacity(0.8) }
            return .red

        // Body Battery: higher = better
        // 75+ High, 50-74 Medium, 25-49 Low, 0-24 Critical
        case .bodyBattery:
            if value >= 75 { return .green }
            if value >= 50 { return .yellow }
            if value >= 25 { return .orange }
            return .red

        // Stress: lower = better (inverted scale)
        // 0-25 Rest, 26-50 Low, 51-75 Medium, 76-100 High
        case .stress:
            if value <= 25 { return .green }
            if value <= 50 { return .yellow }
            if value <= 75 { return .orange }
            return .red

        // VO2 Max: general fitness scale
        // 50+ Excellent, 40-49 Good, 30-39 Fair, <30 Low
        case .vo2Max:
            if value >= 50 { return .green }
            if value >= 40 { return .yellow }
            if value >= 30 { return .orange }
            return .red

        // HRV: uses the status level text from Garmin (BALANCED, UNBALANCED, LOW, POOR)
        case .hrv:
            switch level?.uppercased() {
            case "BALANCED": return .green
            case "UNBALANCED": return .yellow
            case "LOW": return .orange
            case "POOR": return .red
            default: return .primary  // No level info — keep neutral
            }

        // Sleep Score: higher = better
        // 80+ Excellent, 60-79 Good, 40-59 Fair, <40 Poor
        case .sleep:
            if value >= 80 { return .green }
            if value >= 60 { return .yellow }
            if value >= 40 { return .orange }
            return .red

        // Fitness Age: lower = better (scale roughly 18-80)
        case .fitnessAge:
            if value <= 30 { return .green }
            if value <= 45 { return .yellow }
            if value <= 60 { return .orange }
            return .red

        // Training Status: text metric, color from the status level
        case .trainingStatus:
            switch level?.uppercased() {
            case "PRODUCTIVE", "PEAKING": return .green
            case "RECOVERY", "MAINTAINING": return .yellow
            case "UNPRODUCTIVE", "OVERREACHING": return .orange
            case "DETRAINING": return .red
            default: return .primary  // Unknown status — keep neutral
            }

        // Steps: progress toward the user's own daily step goal
        case .stepsToday:
            return progressColor(value: value, goal: goal ?? 10000)

        // Intensity Minutes: progress toward the weekly goal (Garmin default 150)
        case .intensityMinutes:
            return progressColor(value: value, goal: goal ?? 150)

        // Training Load: colored by Garmin's acute:chronic workload status
        case .trainingLoad:
            switch level?.uppercased() {
            case "OPTIMAL": return .green
            case "LOW": return .yellow
            case "HIGH": return .orange
            default: return .primary  // No status — keep neutral
            }

        // Resting HR: lower = better
        // <60 Athletic, 60-69 Good, 70-79 Average, 80+ Elevated
        case .restingHR:
            if value < 60 { return .green }
            if value < 70 { return .yellow }
            if value < 80 { return .orange }
            return .red
        }
    }

    /// Shared zone logic for goal-relative metrics: green once the goal is met,
    /// stepping down through yellow and orange as progress falls off.
    private static func progressColor(value: Double, goal: Double) -> Color {
        guard goal > 0 else { return .primary }
        let progress = value / goal
        if progress >= 1.0 { return .green }
        if progress >= 0.75 { return .yellow }
        if progress >= 0.40 { return .orange }
        return .red
    }

    /// Whether a metric sits in its top zone — the "excellence" state that earns the volt accent.
    static func isTopZone(type: MetricType, value: Double, level: String?, goal: Double? = nil) -> Bool {
        switch type {
        case .readiness: return value >= 80
        case .bodyBattery: return value >= 80
        case .stress: return value <= 25
        case .vo2Max: return value >= 50
        case .hrv: return level?.uppercased() == "BALANCED"
        case .sleep: return value >= 80
        case .fitnessAge: return value <= 30
        case .trainingStatus:
            guard let level else { return false }
            return ["PRODUCTIVE", "PEAKING"].contains(level.uppercased())
        case .stepsToday: return value >= (goal ?? 10000)
        case .restingHR: return value < 60
        case .intensityMinutes: return value >= (goal ?? 150)
        case .trainingLoad: return level?.uppercased() == "OPTIMAL"
        }
    }

    /// Gauge fill color: green for top-zone excellence, zone color otherwise.
    static func gaugeColor(type: MetricType, value: Double, level: String?, goal: Double? = nil) -> Color {
        isTopZone(type: type, value: value, level: level, goal: goal)
        ? Color.green
            : zoneColor(type: type, value: value, level: level, goal: goal)
    }

    /// Formats a metric value for display, stripping a trailing ".0" so whole
    /// numbers stay clean (22.5 -> "22.5", 23.0 -> "23", 48.0 -> "48").
    static func formattedValue(_ value: Double, format: String) -> String {
        var text = String(format: format, value)
        if text.hasSuffix(".0") {
            text.removeLast(2)
        }
        return text
    }

    /// Normalized gauge fill fraction (0...1) showing where the value sits in its scale.
    /// Scales use practical maxima: 100-point metrics map directly, VO2 Max tops out ~80,
    /// and HRV (ms) tops out around 150 for most athletes.
    static func gaugeFraction(type: MetricType, value: Double, goal: Double? = nil) -> Double {
        switch type {
        // Lower-is-better scales: fill grows as the value improves
        case .fitnessAge:
            return min(max((80 - value) / 62, 0), 1)   // 18-80 scale
        case .restingHR:
            return min(max((100 - value) / 60, 0), 1)  // 40-100 scale
        case .trainingStatus:
            return 0  // Text metric — no meaningful fill
        case .stepsToday:
            // Fills against the user's own step goal (10k only as a fallback)
            return min(max(value / (goal ?? 10000), 0), 1)
        case .intensityMinutes:
            // Weekly goal, Garmin's default being 150 minutes
            return min(max(value / (goal ?? 150), 0), 1)
        case .trainingLoad:
            // Position within the optimal-load tunnel (goal = tunnel top)
            return min(max(value / (goal ?? 1000), 0), 1)
        case .vo2Max:
            return min(max(value / 80, 0), 1)          // Practical max ~80
        case .hrv:
            return min(max(value / 150, 0), 1)         // Practical max ~150ms
        default:
            return min(max(value / 100, 0), 1)         // 100-point scales
        }
    }
}

// MARK: - Volt Button Style

/// Primary action button style: volt fill with ink text — the brand's key CTA treatment.
/// Used for Login/Verify actions where the accent signals "the main thing to do".
struct VoltButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(BodilyPalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(BodilyPalette.volt.opacity(configuration.isPressed ? 0.75 : 1))
            )
    }
}

// MARK: - Gauge Bar

/// Thin capsule gauge showing a value's position within its scale — the signature
/// element of the sports-instrument aesthetic. The track is always visible (slate at
/// low opacity) so even empty states still read as an instrument; the fill only
/// appears when data exists.
///
struct GaugeBar: View {
    /// Fill fraction 0...1, or nil when no data is available (track only)
    let fraction: Double?
    /// Zone color or volt accent for the fill
    let fillColor: Color?
    /// Bar thickness — slightly thicker in the host app than in the widget
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track — always rendered so empty states still show the instrument
                Capsule()
                    .fill(BodilyPalette.gaugeTrack)

                // Fill — clamped so tiny values stay visible as a nub
                if let fraction, let fillColor {
                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(geometry.size.width * fraction, 4))
                }
            }
        }
        .frame(height: height)
    }
}

/// A single metric value paired with the date it was sourced from.
/// Allows the widget to show "last updated" labels when data is not from today.
struct MetricEntry: Codable {
    let value: Double?
    let date: String?       // "YYYY-MM-DD" — the date this value is from
    let level: String?      // Optional qualifier (e.g. "LOW", "HIGH" for Training Readiness)
    let goal: Double?       // Optional target (step goal, weekly IM goal, load tunnel top)
    let detail: String?     // Optional secondary display string (e.g. sleep duration)

    /// Explicit init so existing call sites that pass only value/date/level keep
    /// working while goal and detail stay optional.
    init(value: Double?, date: String?, level: String?,
         goal: Double? = nil, detail: String? = nil) {
        self.value = value
        self.date = date
        self.level = level
        self.goal = goal
        self.detail = detail
    }

    /// Whether this metric's data is from today
    var isFromToday: Bool {
        guard let metricDate = date else { return false }
        let todayString = ISO8601DateFormatter.dateOnly.string(from: Date())
        return metricDate == todayString
    }
    
    /// Formatted "last updated" string for display (e.g. "Jul 29")
    var lastUpdatedLabel: String? {
        guard let dateStr = date, !isFromToday else { return nil }
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        guard let parsedDate = inputFormatter.date(from: dateStr) else { return nil }
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMM d"
        return outputFormatter.string(from: parsedDate)
    }
    
    /// Whether this entry has a valid value
    var hasValue: Bool { value != nil }
}

/// Shared data model representing the Garmin daily metrics.
/// Maps directly to the JSON written by the Python fetcher.
/// Both the host app and the widget extension decode from this format.
struct GarminMetrics: Codable {
    let timestamp: String               // ISO 8601 timestamp of last fetch
    let date: String                    // Today's date (YYYY-MM-DD)
    let trainingReadiness: MetricEntry
    let bodyBattery: MetricEntry
    let stressLevel: MetricEntry
    let vo2Max: MetricEntry
    let hrvStatus: MetricEntry
    let sleepScore: MetricEntry
    let fitnessAge: MetricEntry
    let trainingStatus: MetricEntry     // Text metric — status lives in `level`, value is nil
    let stepsToday: MetricEntry
    let restingHR: MetricEntry
    let intensityMinutes: MetricEntry
    let trainingLoad: MetricEntry     // Acute load; ACWR status lives in `level`
    let error: String?

    /// Explicit memberwise init (the synthesized one disappears once a custom
    /// decoder init is defined below).
    init(timestamp: String, date: String,
         trainingReadiness: MetricEntry, bodyBattery: MetricEntry,
         stressLevel: MetricEntry, vo2Max: MetricEntry,
         hrvStatus: MetricEntry, sleepScore: MetricEntry,
         fitnessAge: MetricEntry, trainingStatus: MetricEntry,
         stepsToday: MetricEntry, restingHR: MetricEntry,
         intensityMinutes: MetricEntry, trainingLoad: MetricEntry,
         error: String?) {
        self.timestamp = timestamp
        self.date = date
        self.trainingReadiness = trainingReadiness
        self.bodyBattery = bodyBattery
        self.stressLevel = stressLevel
        self.vo2Max = vo2Max
        self.hrvStatus = hrvStatus
        self.sleepScore = sleepScore
        self.fitnessAge = fitnessAge
        self.trainingStatus = trainingStatus
        self.stepsToday = stepsToday
        self.restingHR = restingHR
        self.intensityMinutes = intensityMinutes
        self.trainingLoad = trainingLoad
        self.error = error
    }

    /// Custom decoding so metrics added after the initial release (fitness age,
    /// training status, steps, resting HR) default to empty entries when reading
    /// JSON files written by older fetcher versions.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        date = try container.decode(String.self, forKey: .date)
        trainingReadiness = try container.decode(MetricEntry.self, forKey: .trainingReadiness)
        bodyBattery = try container.decode(MetricEntry.self, forKey: .bodyBattery)
        stressLevel = try container.decode(MetricEntry.self, forKey: .stressLevel)
        vo2Max = try container.decode(MetricEntry.self, forKey: .vo2Max)
        hrvStatus = try container.decode(MetricEntry.self, forKey: .hrvStatus)
        sleepScore = try container.decode(MetricEntry.self, forKey: .sleepScore)
        let empty = MetricEntry(value: nil, date: nil, level: nil)
        fitnessAge = try container.decodeIfPresent(MetricEntry.self, forKey: .fitnessAge) ?? empty
        trainingStatus = try container.decodeIfPresent(MetricEntry.self, forKey: .trainingStatus) ?? empty
        stepsToday = try container.decodeIfPresent(MetricEntry.self, forKey: .stepsToday) ?? empty
        restingHR = try container.decodeIfPresent(MetricEntry.self, forKey: .restingHR) ?? empty
        intensityMinutes = try container.decodeIfPresent(MetricEntry.self, forKey: .intensityMinutes) ?? empty
        trainingLoad = try container.decodeIfPresent(MetricEntry.self, forKey: .trainingLoad) ?? empty
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    /// Returns a placeholder instance for widget previews
    static var placeholder: GarminMetrics {
        let today = ISO8601DateFormatter.dateOnly.string(from: Date())
        return GarminMetrics(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            date: today,
            trainingReadiness: MetricEntry(value: 65, date: today, level: "MODERATE"),
            bodyBattery: MetricEntry(value: 72, date: today, level: nil),
            stressLevel: MetricEntry(value: 30, date: today, level: nil),
            vo2Max: MetricEntry(value: 48.0, date: today, level: nil),
            hrvStatus: MetricEntry(value: 52, date: today, level: nil),
            sleepScore: MetricEntry(value: 80, date: today, level: nil, detail: "7h 20m"),
            fitnessAge: MetricEntry(value: 31.5, date: today, level: nil),
            trainingStatus: MetricEntry(value: nil, date: today, level: "PRODUCTIVE"),
            stepsToday: MetricEntry(value: 8432, date: today, level: nil, goal: 8000),
            restingHR: MetricEntry(value: 52, date: today, level: nil),
            intensityMinutes: MetricEntry(value: 180, date: today, level: nil, goal: 150),
            trainingLoad: MetricEntry(value: 579, date: today, level: "OPTIMAL", goal: 805),
            error: nil
        )
    }

    /// Returns an empty/unavailable metrics instance
    static var unavailable: GarminMetrics {
        GarminMetrics(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            date: "",
            trainingReadiness: MetricEntry(value: nil, date: nil, level: nil),
            bodyBattery: MetricEntry(value: nil, date: nil, level: nil),
            stressLevel: MetricEntry(value: nil, date: nil, level: nil),
            vo2Max: MetricEntry(value: nil, date: nil, level: nil),
            hrvStatus: MetricEntry(value: nil, date: nil, level: nil),
            sleepScore: MetricEntry(value: nil, date: nil, level: nil),
            fitnessAge: MetricEntry(value: nil, date: nil, level: nil),
            trainingStatus: MetricEntry(value: nil, date: nil, level: nil),
            stepsToday: MetricEntry(value: nil, date: nil, level: nil),
            restingHR: MetricEntry(value: nil, date: nil, level: nil),
            intensityMinutes: MetricEntry(value: nil, date: nil, level: nil),
            trainingLoad: MetricEntry(value: nil, date: nil, level: nil),
            error: "No data available"
        )
    }
}

// MARK: - Metric Catalog

/// Catalog of every metric the host app can display, with presentation metadata.
/// Drives the customizable metrics grid: `visibleMetrics` in AppViewModel stores
/// an ordered subset of these IDs, and the grid renders cards from this catalog.
enum MetricID: String, CaseIterable, Codable, Identifiable {
    case readiness, bodyBattery, stress, vo2Max, hrv, sleep
    case fitnessAge, trainingStatus, stepsToday, restingHR
    case intensityMinutes, trainingLoad

    var id: String { rawValue }

    /// The original six metrics shown before any customization
    static let defaultVisible: [MetricID] = [.readiness, .bodyBattery, .stress, .vo2Max, .hrv, .sleep]

    /// App Group suite shared between the host app and the widget extension
    static let sharedSuiteName = "group.com.bodily.shared"

    /// UserDefaults key the host app writes the ordered selection to
    private static let selectionKey = "bodily.visibleMetrics"

    /// The selection saved by the host app, capped at `maxCount` tiles.
    /// Falls back to the default visible set when nothing has been saved yet.
    static func savedSelection(maxCount: Int = 6) -> [MetricID] {
        let defaults = UserDefaults(suiteName: sharedSuiteName)
        guard let rawValues = defaults?.stringArray(forKey: selectionKey) else {
            return Array(defaultVisible.prefix(maxCount))
        }
        let restored = rawValues.compactMap { MetricID(rawValue: $0) }
        return restored.isEmpty ? Array(defaultVisible.prefix(maxCount)) : Array(restored.prefix(maxCount))
    }

    var title: String {
        switch self {
        case .readiness: return "Training Readiness"
        case .bodyBattery: return "Body Battery"
        case .stress: return "Stress"
        case .vo2Max: return "VO2 Max"
        case .hrv: return "HRV"
        case .sleep: return "Sleep"
        case .fitnessAge: return "Fitness Age"
        case .trainingStatus: return "Training Status"
        case .stepsToday: return "Steps"
        case .restingHR: return "Resting HR"
        case .intensityMinutes: return "Intensity Min"
        case .trainingLoad: return "Training Load"
        }
    }

    var icon: String {
        switch self {
        case .readiness: return "figure.run"
        case .bodyBattery: return "battery.75percent"
        case .stress: return "dumbbell.fill"
        case .vo2Max: return "lungs.fill"
        case .hrv: return "waveform.path.ecg"
        case .sleep: return "bed.double.fill"
        case .fitnessAge: return "figure.arms.open"
        case .trainingStatus: return "chart.line.uptrend.xyaxis"
        case .stepsToday: return "figure.walk"
        case .restingHR: return "heart.fill"
        case .intensityMinutes: return "flame.fill"
        case .trainingLoad: return "chart.bar.fill"
        }
    }

    var type: MetricType {
        switch self {
        case .readiness: return .readiness
        case .bodyBattery: return .bodyBattery
        case .stress: return .stress
        case .vo2Max: return .vo2Max
        case .hrv: return .hrv
        case .sleep: return .sleep
        case .fitnessAge: return .fitnessAge
        case .trainingStatus: return .trainingStatus
        case .stepsToday: return .stepsToday
        case .restingHR: return .restingHR
        case .intensityMinutes: return .intensityMinutes
        case .trainingLoad: return .trainingLoad
        }
    }

    var format: String {
        switch self {
        case .vo2Max, .fitnessAge: return "%.1f"
        default: return "%.0f"
        }
    }

    var unit: String {
        switch self {
        case .hrv: return "ms"
        case .restingHR: return "bpm"
        default: return ""
        }
    }

    /// Pulls this metric's entry out of a decoded metrics payload
    func entry(from metrics: GarminMetrics) -> MetricEntry {
        switch self {
        case .readiness: return metrics.trainingReadiness
        case .bodyBattery: return metrics.bodyBattery
        case .stress: return metrics.stressLevel
        case .vo2Max: return metrics.vo2Max
        case .hrv: return metrics.hrvStatus
        case .sleep: return metrics.sleepScore
        case .fitnessAge: return metrics.fitnessAge
        case .trainingStatus: return metrics.trainingStatus
        case .stepsToday: return metrics.stepsToday
        case .restingHR: return metrics.restingHR
        case .intensityMinutes: return metrics.intensityMinutes
        case .trainingLoad: return metrics.trainingLoad
        }
    }
}

// MARK: - Timestamp Formatting

extension GarminMetrics {

    /// Formats the fetch timestamp as "Last updated: Today 13:35" or "Last updated: Jul 29 13:35".
    /// Shared by the widget header and the host app so both surfaces read identically.
    var formattedLastUpdated: String {
        guard let date = parsedFetchTimestamp else {
            return "Last updated: --:--"
        }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: date)

        // Relative phrasing when the fetch happened today; absolute date otherwise
        if Calendar.current.isDateInToday(date) {
            return "Last updated: Today \(timeString)"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            return "Last updated: \(dateFormatter.string(from: date)) \(timeString)"
        }
    }

    /// Parses the ISO timestamp written by the Python fetcher, trying fractional seconds,
    /// standard ISO 8601, and local formats without timezone in turn.
    private var parsedFetchTimestamp: Date? {
        // Try with fractional seconds (fetcher outputs "2026-07-30T04:06:14.265529")
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: timestamp) { return date }

        // Try standard ISO 8601
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: timestamp) { return date }

        // Fallback: local timestamp without timezone
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            local.dateFormat = format
            if let date = local.date(from: timestamp) { return date }
        }
        return nil
    }
}

/// Extension for date-only ISO formatting used by MetricEntry
extension ISO8601DateFormatter {
    static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}


/// Handles reading metrics from the shared App Group container.
/// Used by both the widget extension and the host app.
class MetricsReader {
    
    /// App Group identifier — must match the one configured in Xcode entitlements
    static let appGroupID = "group.com.bodily.shared"
    
    /// Reads the latest metrics from the shared JSON file.
    /// Returns nil if the file doesn't exist or can't be decoded.
    static func readLatestMetrics() -> GarminMetrics? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            print("[MetricsReader] Failed to get App Group container URL")
            return nil
        }
        
        let fileURL = containerURL.appendingPathComponent("garmin_metrics.json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[MetricsReader] Metrics file not found at: \(fileURL.path)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let metrics = try decoder.decode(GarminMetrics.self, from: data)
            return metrics
        } catch {
            print("[MetricsReader] Failed to decode metrics: \(error)")
            return nil
        }
    }
    
    /// Returns how long ago the metrics were last updated.
    /// Useful for showing staleness indicators in the widget.
    static func timeSinceLastUpdate() -> TimeInterval? {
        guard let metrics = readLatestMetrics() else { return nil }
        
        // Try multiple timestamp formats (fetcher outputs fractional seconds without timezone)
        let parsers: [(String) -> Date?] = [
            { str in
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f.date(from: str)
            },
            { str in ISO8601DateFormatter().date(from: str) },
            { str in
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f.date(from: str)
            },
            { str in
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f.date(from: str)
            }
        ]
        
        for parser in parsers {
            if let date = parser(metrics.timestamp) {
                return Date().timeIntervalSince(date)
            }
        }
        return nil
    }
}
