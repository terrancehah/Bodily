import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

/// Main content view of the Bodily host app.
/// Minimalist design inspired by Strava/Runna — clean, data-forward, no visual noise.
struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var showLoginSheet = false
    @State private var showAccountSheet = false
    /// Expansion state of the customize-metrics drawer
    @State private var isCustomizeExpanded = false
    /// The card currently being dragged — tracked in state so drop delegates can
    /// live-rearrange the grid as the drag moves over other cards
    @State private var draggedMetric: MetricID?
    /// Timestamp of the last live reorder — used as a cooldown to prevent
    /// cascading swaps when cards shift under the cursor during a drag
    @State private var lastSwapTime: Date = .distantPast
    /// Width of a single grid card, captured via GeometryReader so the
    /// drop delegate can compute the horizontal midpoint for before/after logic
    @State private var cardWidth: CGFloat = 115
    
    var body: some View {
        // No fixed height — the window sizes itself to the content, growing when
        // the customize panel opens and shrinking back when it closes
        VStack(alignment: .leading, spacing: 0) {
            // Header: app name + connection indicator
            headerSection

            // Metrics grid with inline refresh
            metricsSection

            // Minimal footer actions
            footerSection
        }
        .padding(28)
        .frame(width: 420)
        // Slate-tinted window surface ties the app to the widget's instrument look
        .background(BodilyPalette.surface)
        .onAppear {
            viewModel.loadStatus()
        }
        .sheet(isPresented: $showLoginSheet, onDismiss: {
            viewModel.resetLoginState()
        }) {
            LoginView(viewModel: viewModel, onDismiss: { showLoginSheet = false })
        }
        .sheet(isPresented: $showAccountSheet) {
            AccountView(viewModel: viewModel, onDismiss: { showAccountSheet = false })
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 7) {
            // Volt dot + tracked wordmark — same brand mark as the widget header
//            Circle()
//                .fill(BodilyPalette.voltAccent)
//                .frame(width: 7, height: 7)

            Text("BODILY")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(2)

            Spacer()

            // Connection status + last-updated timestamp, stacked on the trailing edge
            VStack(alignment: .trailing, spacing: 2) {
                // Green when live, red when disconnected
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.isConnected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)

                    Text(viewModel.isConnected ? "Connected to Garmin" : "Not connected")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(BodilyPalette.secondaryText)
                }

                // Same "Last updated" phrasing as the widget header
                if let metrics = viewModel.currentMetrics {
                    Text(metrics.formattedLastUpdated)
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(BodilyPalette.tertiaryText)
                }
            }
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Metrics
    
    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section title with animated refresh button
            HStack(alignment: .center) {
                Text("Current Metrics")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BodilyPalette.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Spacer()

                // Refresh button: fetches data + reloads widget — volt marks it as the live action
                Button(action: { viewModel.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BodilyPalette.secondaryText)
                        .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                        .animation(
                            viewModel.isRefreshing
                                ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                : .default,
                            value: viewModel.isRefreshing
                        )
                }
                .buttonStyle(.plain)
                .help("Fetch latest data and refresh widget")
                .disabled(viewModel.isRefreshing)
            }
            
            if let metrics = viewModel.currentMetrics {
                if viewModel.visibleMetrics.isEmpty {
                    // All metrics hidden — the hint doubles as a drop target to add one back
                    Text("All metrics are hidden. Tap Customize Metrics below, then drag a card up here.")
                        .font(.system(size: 11))
                        .foregroundStyle(BodilyPalette.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .onDrop(of: [UTType.plainText],
                                delegate: GridEndDropDelegate(draggedMetric: $draggedMetric, lastSwapTime: $lastSwapTime, viewModel: viewModel))
                } else {
                    // Grid renders from the user's ordered selection (3 cards per row)
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(viewModel.visibleMetrics) { metricID in
                            gridCard(metricID, from: metrics)
                        }
                    }
                    .background(
                        // Capture the grid's width to derive card width for
                        // the drop delegate's horizontal midpoint threshold
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    cardWidth = max((geo.size.width - 20) / 3, 80)
                                }
                        }
                    )
                }

                // Customize toggle + extra-metrics pool (drag cards between the two)
                customizeToggle
                if isCustomizeExpanded {
                    moreMetricsSection(from: metrics)
                }
            } else {
                // Empty state — ghosted gauges teach the layout before data arrives
                VStack(spacing: 12) {
                    // Three placeholder gauges mirror the eventual metric rows
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { _ in
                            GaugeBar(fraction: nil, fillColor: nil, height: 3)
                        }
                    }
                    .padding(.horizontal, 24)

                    Text("No metrics yet")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(BodilyPalette.secondaryText)
                    Text("Log in with your Garmin account and your daily readiness, recovery, and sleep scores will appear here — and on your desktop widget.")
                        .font(.system(size: 11))
                        .foregroundStyle(BodilyPalette.tertiaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }

            // Last updated timestamp
            if let lastUpdate = viewModel.lastUpdateTime {
                Text("Last updated: \(lastUpdate)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(BodilyPalette.tertiaryText)
                    .padding(.top, 4)
            }

        }
        .padding(.bottom, 20)
        // Dropping on empty space inside the section moves the card to the end
        .onDrop(of: [UTType.plainText],
                delegate: GridEndDropDelegate(draggedMetric: $draggedMetric, lastSwapTime: $lastSwapTime, viewModel: viewModel))
    }

    // MARK: - Customize Mode

    /// A metric card for the main grid. In customize mode the card becomes a drag
    /// source and a drop target — the grid shuffles live as the drag moves over it.
    @ViewBuilder
    private func gridCard(_ metricID: MetricID, from metrics: GarminMetrics) -> some View {
        if isCustomizeExpanded {
            metricCard(for: metricID, from: metrics)
                // Fade the card being dragged so the shuffle reads clearly
                .opacity(draggedMetric == metricID ? 0.4 : 1)
                .onDrag {
                    draggedMetric = metricID
                    return NSItemProvider(object: metricID.id as NSString)
                }
                .onDrop(of: [UTType.plainText],
                        delegate: GridCardDropDelegate(target: metricID, draggedMetric: $draggedMetric, lastSwapTime: $lastSwapTime, cardWidth: cardWidth, viewModel: viewModel))
        } else {
            metricCard(for: metricID, from: metrics)
        }
    }

    /// Builds a metric card from the catalog — single construction site so the
    /// main grid and the extra-metrics pool always render identically.
    private func metricCard(for metricID: MetricID, from metrics: GarminMetrics) -> MetricCard {
        MetricCard(
            title: metricID.title,
            metric: metricID.entry(from: metrics),
            type: metricID.type,
            format: metricID.format,
            unit: metricID.unit,
            icon: metricID.icon
        )
    }

    /// Button that opens/closes customize mode. Opening expands the window to
    /// reveal the extra-metrics pool; closing snaps it back to the grid alone.
    private var customizeToggle: some View {
        HStack {
            if isCustomizeExpanded {
                Spacer()
                // Volt fill makes the exit from customize mode unmissable
                Button("Done") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isCustomizeExpanded = false
                    }
                    // Final widget sync once the layout is settled
                    viewModel.reloadWidgetTimelines()
                }
                .buttonStyle(VoltButtonStyle())
            } else {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isCustomizeExpanded = true
                    }
                }) {
                    Label("Customize Metrics", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(BodilyPalette.secondaryText)
            }
        }
        .padding(.top, 12)
    }

    /// Pool of hidden metrics rendered as dimmed cards. Drag a card up into the
    /// main grid to add it; drag a grid card down here to hide it.
    private func moreMetricsSection(from metrics: GarminMetrics) -> some View {
        let hiddenMetrics = MetricID.allCases.filter { !viewModel.visibleMetrics.contains($0) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("MORE METRICS")
                .font(.system(size: 9, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(BodilyPalette.tertiaryText)

            Text("Drag a card up to add it — a full grid swaps the card you drop on. The widget mirrors this layout.")
                .font(.system(size: 10))
                .foregroundStyle(BodilyPalette.tertiaryText)
                // Allow the hint to grow vertically instead of truncating to one line
                .fixedSize(horizontal: false, vertical: true)

            if hiddenMetrics.isEmpty {
                // Every metric is visible — a dashed drop zone keeps "hide" possible
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(BodilyPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(height: 60)
                    .overlay(
                        Text("Drop here to hide")
                            .font(.system(size: 10))
                            .foregroundStyle(BodilyPalette.tertiaryText)
                    )
                    .onDrop(of: [UTType.plainText],
                            delegate: MetricPoolDropDelegate(draggedMetric: $draggedMetric, viewModel: viewModel))
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(hiddenMetrics) { metricID in
                        metricCard(for: metricID, from: metrics)
                            // Dimmed to signal "not on the panel"
                            .opacity(draggedMetric == metricID ? 0.4 : 0.55)
                            .onDrag {
                                draggedMetric = metricID
                                return NSItemProvider(object: metricID.id as NSString)
                            }
                    }
                }
                // The whole pool accepts drops: a grid card dropped here gets hidden
                .onDrop(of: [UTType.plainText],
                        delegate: MetricPoolDropDelegate(draggedMetric: $draggedMetric, viewModel: viewModel))
            }
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Footer Actions
    
    private var footerSection: some View {
        HStack(spacing: 16) {
            // View log
            Button(action: { viewModel.openLog() }) {
                Label("View Log", systemImage: "doc.text")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Spacer()
            
            // Settings button (when connected) or Login button (when not connected)
            if viewModel.hasExistingAuth {
                Button(action: { showAccountSheet = true }) {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                // Login is the primary CTA — volt fill with ink text
                Button(action: { showLoginSheet = true }) {
                    Label("Login", systemImage: "person.badge.key")
                }
                .buttonStyle(VoltButtonStyle())
            }
        }
    }
}

/// A single metric card for the host app — the instrument-panel counterpart of the
/// widget tile. Slate-tinted fill with a hairline border, bold zone-colored value,
/// tracked small-caps label, and the signature gauge bar along the bottom.
struct MetricCard: View {
    let title: String
    let metric: MetricEntry
    let type: MetricType
    var format: String = "%.0f"
    var unit: String = ""
    var icon: String = "circle"

    /// Title line with the stale source date appended inline (e.g. "SLEEP · JUL 29").
    /// Always a single row, so outdated cards never grow taller than fresh ones —
    /// same treatment as the widget tile.
    private var titleText: Text {
        let base = Text(title.uppercased()).foregroundStyle(BodilyPalette.secondaryText)
        guard let updatedLabel = metric.lastUpdatedLabel else { return base }
        return base + Text(" · \(updatedLabel.uppercased())").foregroundStyle(BodilyPalette.tertiaryText)
    }

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

    var body: some View {
        VStack(spacing: 1) {
            
            // Section 1: Readings + Details — flexible height, top-aligned so
            // the value row always starts at the same position across cards
            VStack(alignment: .center, spacing: 0) {
                // Icon + color-coded value — the value is the hero
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

            // Section 2: GaugeBar — always present so every card has the same
            // structural rhythm. Text metrics like Training Status get a fill
            // derived from their status level.
            GaugeBar(fraction: gaugeFraction, fillColor: gaugeFillColor, height: 3)
                .padding(.horizontal, 10)
                .padding(.top, 6)

            // Section 3: Title — pinned to the bottom so labels align across
            // every card in a row regardless of detail-line presence
            titleText
                .font(.system(size: 8, weight: .medium))
                .tracking(0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        // Slate-tinted fill with a hairline border — instrument panel, not gray box
        .background(RoundedRectangle(cornerRadius: 10).fill(BodilyPalette.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BodilyPalette.hairline, lineWidth: 1))
    }
}


// MARK: - Drop Delegates

/// Drop delegate for a card in the main grid. Live-rearranges the grid as the
/// drag moves over cards, using a cooldown + cursor-location threshold to prevent
/// the cascading oscillation that happens when cards shift under the cursor.
///
/// The swap logic lives in `dropUpdated` (fires continuously while hovering) rather
/// than `dropEntered` (fires once on frame entry). After a swap, the reordered cards
/// animate to new positions — a different card may slide under the cursor and trigger
/// its own entry. The 250ms cooldown breaks that cascade by suppressing consecutive
/// swaps. The horizontal midpoint check adds directional intent: left half of the
/// target inserts before, right half inserts after.
private struct GridCardDropDelegate: DropDelegate {
    let target: MetricID
    @Binding var draggedMetric: MetricID?
    @Binding var lastSwapTime: Date
    let cardWidth: CGFloat
    let viewModel: AppViewModel

    /// No swap on entry — prevents the initial cascade when cards shift after a
    /// reorder. Swap logic is in `dropUpdated` with cooldown + location threshold.
    func dropEntered(info: DropInfo) {
        // Intentionally empty — see dropUpdated for the actual swap logic
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let dragged = draggedMetric, dragged != target else {
            return DropProposal(operation: .move)
        }

        // Cooldown: suppress rapid cascading swaps after a reorder. Without this,
        // each swap shifts cards, a new card enters the cursor's frame, and its
        // dropUpdated fires immediately — causing the oscillation the user sees.
        let now = Date()
        guard now.timeIntervalSince(lastSwapTime) > 0.25 else {
            return DropProposal(operation: .move)
        }

        // Live-shuffle only for cards already in the grid — a pool card joining
        // a full grid swaps on release, not on hover (hover-swapping feels chaotic)
        let draggedIsVisible = viewModel.visibleMetrics.contains(dragged)
        let gridFull = viewModel.visibleMetrics.count >= AppViewModel.maxVisibleMetrics
        guard draggedIsVisible || !gridFull else {
            return DropProposal(operation: .move)
        }

        // Location threshold: cursor past the horizontal midpoint inserts after
        // the target; before the midpoint inserts before. This gives the user
        // directional control and prevents the same card from repeatedly swapping
        // back and forth at the boundary.
        let isRightHalf = info.location.x > cardWidth / 2

        withAnimation(.easeInOut(duration: 0.2)) {
            if isRightHalf {
                viewModel.moveOrInsert(dragged, after: target)
            } else {
                viewModel.moveOrInsert(dragged, before: target)
            }
        }
        lastSwapTime = now

        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        // Finalize the drop — performs the swap if it hasn't already happened via
        // dropUpdated (e.g., a pool card landing on a full grid, or the cooldown
        // was active when the user released)
        if let dragged = draggedMetric {
            let isRightHalf = info.location.x > cardWidth / 2
            withAnimation(.easeInOut(duration: 0.2)) {
                if isRightHalf {
                    viewModel.moveOrInsert(dragged, after: target)
                } else {
                    viewModel.moveOrInsert(dragged, before: target)
                }
            }
        }
        draggedMetric = nil
        viewModel.reloadWidgetTimelines()
        return true
    }
}

/// Drop delegate for the extra-metrics pool. A grid card released here is hidden;
/// the widget is reloaded only now that the drag has finished.
private struct MetricPoolDropDelegate: DropDelegate {
    @Binding var draggedMetric: MetricID?
    let viewModel: AppViewModel

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedMetric = nil }
        guard let dragged = draggedMetric,
              viewModel.visibleMetrics.contains(dragged) else { return false }
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.hideMetric(dragged)
        }
        viewModel.reloadWidgetTimelines()
        return true
    }
}

/// Drop delegate for empty space in the metrics section — hovering it sends the
/// dragged card to the end of the grid. Uses the same cooldown as GridCardDropDelegate
/// to prevent the card from rapidly oscillating between the end and its prior slot.
private struct GridEndDropDelegate: DropDelegate {
    @Binding var draggedMetric: MetricID?
    @Binding var lastSwapTime: Date
    let viewModel: AppViewModel

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedMetric, viewModel.visibleMetrics.last != dragged else { return }
        // Cooldown: same threshold as GridCardDropDelegate to prevent cascading
        let now = Date()
        guard now.timeIntervalSince(lastSwapTime) > 0.25 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.moveOrAppend(dragged)
        }
        lastSwapTime = now
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        // Safety net: if the cooldown blocked the live move in dropEntered,
        // finalize the move on release
        if let dragged = draggedMetric, viewModel.visibleMetrics.last != dragged {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.moveOrAppend(dragged)
            }
        }
        draggedMetric = nil
        viewModel.reloadWidgetTimelines()
        return true
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
