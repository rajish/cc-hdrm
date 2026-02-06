import SwiftUI
import os

/// Main content view for the analytics window.
///
/// Layout:
/// - Title bar with "Usage Analytics" and close button
/// - Controls row: TimeRangeSelector (left) + series toggles (right)
/// - UsageChart (expands to fill available space)
/// - HeadroomBreakdownBar (fixed 80px height)
struct AnalyticsView: View {
    var onClose: () -> Void
    let historicalDataService: any HistoricalDataServiceProtocol
    let appState: AppState

    // Default to .week — shows recent trends without overwhelming detail.
    // 24h is too narrow for first impression; 30d/All require rollup data that may be sparse early on.
    @State private var selectedTimeRange: TimeRange = .week
    @State private var fiveHourVisible: Bool = true
    @State private var sevenDayVisible: Bool = true

    @State private var chartData: [UsagePoll] = []
    @State private var rollupData: [UsageRollup] = []
    @State private var resetEvents: [ResetEvent] = []
    @State private var isLoading: Bool = false
    /// Tracks whether any historical data exists in the database (across all time ranges).
    /// Set to true once any successful load returns data. Used to distinguish
    /// "no data yet" (fresh install) from "no data for this range".
    @State private var hasAnyHistoricalData: Bool = false

    /// Tracks the in-flight data load task so rapid time-range switches cancel previous loads.
    @State private var loadTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "analytics"
    )

    var body: some View {
        VStack(spacing: 12) {
            titleBar
            controlsRow
            UsageChart(
                pollData: chartData,
                rollupData: rollupData,
                timeRange: selectedTimeRange,
                fiveHourVisible: fiveHourVisible,
                sevenDayVisible: sevenDayVisible,
                isLoading: isLoading,
                hasAnyHistoricalData: hasAnyHistoricalData
            )
            HeadroomBreakdownBar(
                resetEvents: resetEvents,
                creditLimits: appState.creditLimits
            )
        }
        .padding()
        .task {
            await loadData()
        }
        .onChange(of: selectedTimeRange) { _, _ in
            loadTask?.cancel()
            loadTask = Task { await loadData() }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        // Rollup update is best-effort — failure must not block data display.
        // The sparkline proves data exists in usage_polls; if rollups fail,
        // queries still return raw polls for recent ranges.
        do {
            try await historicalDataService.ensureRollupsUpToDate()
        } catch {
            Self.logger.warning("Rollup update failed (data query will proceed): \(error.localizedDescription)")
        }

        do {
            try Task.checkCancellation()

            switch selectedTimeRange {
            case .day:
                chartData = try await historicalDataService.getRecentPolls(hours: 24)
                rollupData = []
            case .week, .month, .all:
                rollupData = try await historicalDataService.getRolledUpData(range: selectedTimeRange)
                chartData = []
            }
            try Task.checkCancellation()

            resetEvents = try await historicalDataService.getResetEvents(range: selectedTimeRange)

            // Track whether any data has ever been loaded (for fresh-install empty state)
            if !hasAnyHistoricalData && (chartData.count + rollupData.count) > 0 {
                hasAnyHistoricalData = true
            }
        } catch is CancellationError {
            // Task was cancelled by a newer time-range switch — discard silently
        } catch {
            // Log error, keep previous data visible, do not crash
            Self.logger.error("Analytics data load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            Text("Usage Analytics")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close analytics window")
        }
    }

    // MARK: - Controls Row

    private var controlsRow: some View {
        HStack {
            TimeRangeSelector(selected: $selectedTimeRange)
            Spacer()
            seriesToggles
        }
    }

    // MARK: - Series Toggles

    private var seriesToggles: some View {
        HStack(spacing: 8) {
            seriesToggleButton(
                label: "5h",
                isActive: $fiveHourVisible,
                accessibilityPrefix: "5-hour series"
            )

            Text("|")
                .font(.caption)
                .foregroundStyle(.quaternary)

            seriesToggleButton(
                label: "7d",
                isActive: $sevenDayVisible,
                accessibilityPrefix: "7-day series"
            )
        }
    }

    private func seriesToggleButton(
        label: String,
        isActive: Binding<Bool>,
        accessibilityPrefix: String
    ) -> some View {
        Button(action: {
            isActive.wrappedValue.toggle()
        }) {
            HStack(spacing: 4) {
                Image(systemName: isActive.wrappedValue ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .foregroundStyle(isActive.wrappedValue ? Color.accentColor : .secondary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(isActive.wrappedValue ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityPrefix), \(isActive.wrappedValue ? "enabled" : "disabled")")
        .accessibilityHint("Press to toggle")
    }
}

#if DEBUG
#Preview {
    AnalyticsView(
        onClose: {},
        historicalDataService: PreviewHistoricalDataService(),
        appState: AppState()
    )
    .frame(width: 600, height: 500)
}

/// Minimal stub for SwiftUI previews only.
private struct PreviewHistoricalDataService: HistoricalDataServiceProtocol {
    func persistPoll(_ response: UsageResponse) async throws {}
    func persistPoll(_ response: UsageResponse, tier: String?) async throws {}
    func getRecentPolls(hours: Int) async throws -> [UsagePoll] { [] }
    func getLastPoll() async throws -> UsagePoll? { nil }
    func getResetEvents(fromTimestamp: Int64?, toTimestamp: Int64?) async throws -> [ResetEvent] { [] }
    func getResetEvents(range: TimeRange) async throws -> [ResetEvent] { [] }
    func getDatabaseSize() async throws -> Int64 { 0 }
    func ensureRollupsUpToDate() async throws {}
    func getRolledUpData(range: TimeRange) async throws -> [UsageRollup] { [] }
    func pruneOldData(retentionDays: Int) async throws {}
}
#endif
