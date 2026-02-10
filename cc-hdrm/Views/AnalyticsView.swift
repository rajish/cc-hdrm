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
    let headroomAnalysisService: any HeadroomAnalysisServiceProtocol

    /// Per-time-range toggle state for series visibility.
    /// Defaults both series to visible; stored as a simple value type for `@State` compatibility.
    /// Internal (not private) for `@testable import` in unit tests.
    internal struct SeriesVisibility: Equatable {
        var fiveHour: Bool = true
        var sevenDay: Bool = true
    }

    // Default to .week — shows recent trends without overwhelming detail.
    // 24h is too narrow for first impression; 30d/All require rollup data that may be sparse early on.
    @State private var selectedTimeRange: TimeRange = .week
    /// Per-time-range series visibility. Unvisited ranges are absent and default to both-visible.
    /// Session-only — resets when the analytics window is closed and reopened.
    @State private var seriesVisibility: [TimeRange: SeriesVisibility] = [:]

    /// Whether the 5-hour series is visible for the currently selected time range.
    private var fiveHourVisible: Bool {
        seriesVisibility[selectedTimeRange]?.fiveHour ?? true
    }

    /// Whether the 7-day series is visible for the currently selected time range.
    private var sevenDayVisible: Bool {
        seriesVisibility[selectedTimeRange]?.sevenDay ?? true
    }

    /// Binding that reads/writes 5-hour visibility for the current time range.
    private var fiveHourBinding: Binding<Bool> {
        Binding(
            get: { seriesVisibility[selectedTimeRange]?.fiveHour ?? true },
            set: { seriesVisibility[selectedTimeRange, default: SeriesVisibility()].fiveHour = $0 }
        )
    }

    /// Binding that reads/writes 7-day visibility for the current time range.
    private var sevenDayBinding: Binding<Bool> {
        Binding(
            get: { seriesVisibility[selectedTimeRange]?.sevenDay ?? true },
            set: { seriesVisibility[selectedTimeRange, default: SeriesVisibility()].sevenDay = $0 }
        )
    }

    @State private var chartData: [UsagePoll] = []
    @State private var rollupData: [UsageRollup] = []
    @State private var resetEvents: [ResetEvent] = []
    @State private var allTimeResetEvents: [ResetEvent] = []
    @State private var isLoading: Bool = false
    /// Tracks whether any historical data exists in the database (across all time ranges).
    /// Set to true once any successful load returns data. Used to distinguish
    /// "no data yet" (fresh install) from "no data for this range".
    @State private var hasAnyHistoricalData: Bool = false

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
                creditLimits: appState.creditLimits,
                headroomAnalysisService: headroomAnalysisService,
                selectedTimeRange: selectedTimeRange
            )
            ContextAwareValueSummary(
                timeRange: selectedTimeRange,
                resetEvents: resetEvents,
                allTimeResetEvents: allTimeResetEvents,
                creditLimits: appState.creditLimits,
                headroomAnalysisService: headroomAnalysisService
            )
        }
        .padding()
        .task(id: selectedTimeRange) {
            await loadData()
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await Self.fetchData(
                for: selectedTimeRange,
                using: historicalDataService,
                existingAllTimeEvents: allTimeResetEvents.isEmpty ? nil : allTimeResetEvents
            )
            chartData = result.chartData
            rollupData = result.rollupData
            resetEvents = result.resetEvents
            allTimeResetEvents = result.allTimeResetEvents

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

    /// Result of a data fetch for a given time range.
    ///
    /// - Important: Internal visibility for `@testable import` only.
    ///   All three arrays default to empty — callers rely on this to clear
    ///   stale data from a previous time range (e.g., switching from `.week`
    ///   to `.day` clears `rollupData` because it stays at `[]`).
    struct DataLoadResult {
        var chartData: [UsagePoll] = []
        var rollupData: [UsageRollup] = []
        var resetEvents: [ResetEvent] = []
        var allTimeResetEvents: [ResetEvent] = []
    }

    /// Fetches analytics data for the given time range.
    ///
    /// Extracted from `loadData()` for testability. The view's `loadData()`
    /// delegates here and applies the results to `@State` properties.
    ///
    /// - Parameters:
    ///   - range: Time range to fetch data for
    ///   - service: Historical data service to query
    /// - Returns: Fetched chart data, rollup data, and reset events
    /// - Throws: `CancellationError` on rapid range switching, or data service errors
    static func fetchData(
        for range: TimeRange,
        using service: any HistoricalDataServiceProtocol,
        existingAllTimeEvents: [ResetEvent]? = nil
    ) async throws -> DataLoadResult {
        // Rollup update is best-effort — failure must not block data display.
        // The sparkline proves data exists in usage_polls; if rollups fail,
        // queries still return raw polls for recent ranges.
        do {
            try await service.ensureRollupsUpToDate()
        } catch {
            logger.warning("Rollup update failed (data query will proceed): \(error.localizedDescription)")
        }

        try Task.checkCancellation()

        var chartData: [UsagePoll] = []
        var rollupData: [UsageRollup] = []

        switch range {
        case .day:
            chartData = try await service.getRecentPolls(hours: 24)
            rollupData = []  // Explicitly clear stale rollup data from previous range
        case .week, .month, .all:
            rollupData = try await service.getRolledUpData(range: range)
            chartData = []   // Explicitly clear stale poll data from previous range
        }

        try Task.checkCancellation()

        let resetEvents = try await service.getResetEvents(range: range)

        // Reuse cached all-time events when available to avoid redundant DB queries on range switch.
        let allTimeResetEvents: [ResetEvent]
        if range == .all {
            // Range-specific events already cover all time — reuse them.
            allTimeResetEvents = resetEvents
        } else if let existing = existingAllTimeEvents, !existing.isEmpty {
            allTimeResetEvents = existing
        } else {
            try Task.checkCancellation()
            allTimeResetEvents = try await service.getResetEvents(range: .all)
        }

        return DataLoadResult(
            chartData: chartData,
            rollupData: rollupData,
            resetEvents: resetEvents,
            allTimeResetEvents: allTimeResetEvents
        )
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
            .focusEffectDisabled()
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
                color: .headroomNormal,
                isActive: fiveHourBinding,
                accessibilityPrefix: "5-hour series"
            )

            Text("|")
                .font(.caption)
                .foregroundStyle(.quaternary)

            seriesToggleButton(
                label: "7d",
                color: StepAreaChartView.sevenDayColor,
                isActive: sevenDayBinding,
                accessibilityPrefix: "7-day series"
            )
        }
    }

    private func seriesToggleButton(
        label: String,
        color: Color,
        isActive: Binding<Bool>,
        accessibilityPrefix: String
    ) -> some View {
        Button(action: {
            isActive.wrappedValue.toggle()
        }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isActive.wrappedValue ? color : .secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(isActive.wrappedValue ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel("\(accessibilityPrefix), \(isActive.wrappedValue ? "enabled" : "disabled")")
        .accessibilityHint("Press to toggle")
    }
}

#if DEBUG
#Preview {
    AnalyticsView(
        onClose: {},
        historicalDataService: PreviewHistoricalDataService(),
        appState: AppState(),
        headroomAnalysisService: PreviewAnalyticsHeadroomService()
    )
    .frame(width: 600, height: 500)
}

/// Minimal stub for HeadroomAnalysisServiceProtocol in previews only.
private struct PreviewAnalyticsHeadroomService: HeadroomAnalysisServiceProtocol {
    func analyzeResetEvent(fiveHourPeak: Double, sevenDayUtil: Double, creditLimits: CreditLimits) -> HeadroomBreakdown {
        HeadroomBreakdown(usedPercent: 52, constrainedPercent: 12, unusedPercent: 36,
                          usedCredits: 286_000, constrainedCredits: 66_000, unusedCredits: 198_000)
    }

    func aggregateBreakdown(events: [ResetEvent]) -> PeriodSummary {
        PeriodSummary(usedCredits: 2_860_000, constrainedCredits: 660_000, unusedCredits: 1_980_000,
                      resetCount: events.count, avgPeakUtilization: 52.0,
                      usedPercent: 52, constrainedPercent: 12, unusedPercent: 36)
    }
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
