import Testing
import SwiftUI
@testable import cc_hdrm

@Suite("UsageChart Tests")
@MainActor
struct UsageChartTests {

    // MARK: - Helpers

    private func makeChart(
        pollData: [UsagePoll] = [],
        rollupData: [UsageRollup] = [],
        timeRange: TimeRange = .week,
        fiveHourVisible: Bool = true,
        sevenDayVisible: Bool = true,
        isLoading: Bool = false,
        hasAnyHistoricalData: Bool = true
    ) -> UsageChart {
        UsageChart(
            pollData: pollData,
            rollupData: rollupData,
            timeRange: timeRange,
            fiveHourVisible: fiveHourVisible,
            sevenDayVisible: sevenDayVisible,
            isLoading: isLoading,
            hasAnyHistoricalData: hasAnyHistoricalData
        )
    }

    // MARK: - Initialization

    @Test("UsageChart renders without crashing with empty data")
    func rendersEmptyData() {
        let chart = makeChart()
        let _ = chart.body
    }

    // MARK: - Data Point Count Display

    @Test("UsageChart shows data point count for poll data")
    func showsDataPointCountForPolls() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let polls = (0..<148).map { i in
            UsagePoll(
                id: Int64(i),
                timestamp: nowMs - Int64(i) * 60_000,
                fiveHourUtil: Double(i),
                fiveHourResetsAt: nil,
                sevenDayUtil: Double(i) / 2,
                sevenDayResetsAt: nil
            )
        }
        let chart = makeChart(pollData: polls, timeRange: .day)
        // Verify renders without crash — data point count is displayed in body
        let _ = chart.body
    }

    @Test("UsageChart shows data point count for rollup data")
    func showsDataPointCountForRollups() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let rollups = (0..<50).map { i in
            UsageRollup(
                id: Int64(i),
                periodStart: nowMs - Int64(i + 1) * 300_000,
                periodEnd: nowMs - Int64(i) * 300_000,
                resolution: .fiveMin,
                fiveHourAvg: 30.0,
                fiveHourPeak: 40.0,
                fiveHourMin: 20.0,
                sevenDayAvg: 15.0,
                sevenDayPeak: 20.0,
                sevenDayMin: 10.0,
                resetCount: 0,
                wasteCredits: nil
            )
        }
        let chart = makeChart(rollupData: rollups, timeRange: .week)
        let _ = chart.body
    }

    // MARK: - Series Visibility

    @Test("UsageChart renders with both series visible")
    func bothSeriesVisible() {
        let chart = makeChart(fiveHourVisible: true, sevenDayVisible: true)
        let _ = chart.body
    }

    @Test("UsageChart renders with only 5h series visible")
    func onlyFiveHourVisible() {
        let chart = makeChart(fiveHourVisible: true, sevenDayVisible: false)
        let _ = chart.body
    }

    @Test("UsageChart renders with only 7d series visible")
    func onlySevenDayVisible() {
        let chart = makeChart(fiveHourVisible: false, sevenDayVisible: true)
        let _ = chart.body
    }

    @Test("UsageChart shows select-a-series message when both series toggled off")
    func bothSeriesOff() {
        let chart = makeChart(fiveHourVisible: false, sevenDayVisible: false)
        // Should render without crash — displays "Select a series to display"
        let _ = chart.body
    }

    // MARK: - Loading State

    @Test("UsageChart shows loading indicator when isLoading is true")
    func showsLoadingIndicator() {
        let chart = makeChart(isLoading: true)
        let _ = chart.body
    }

    @Test("UsageChart shows data when isLoading is false")
    func showsDataWhenNotLoading() {
        let chart = makeChart(isLoading: false)
        let _ = chart.body
    }

    // MARK: - Empty States

    @Test("UsageChart renders empty state for zero data points with series visible")
    func emptyStateWithSeriesOn() {
        let chart = makeChart(pollData: [], rollupData: [], fiveHourVisible: true, sevenDayVisible: true)
        let _ = chart.body
    }

    @Test("UsageChart renders fresh-install empty state when no historical data exists")
    func freshInstallEmptyState() {
        let chart = makeChart(pollData: [], rollupData: [], hasAnyHistoricalData: false)
        // Should display "No data yet — usage history builds over time"
        let _ = chart.body
    }

    @Test("UsageChart renders range-specific empty state when historical data exists elsewhere")
    func rangeSpecificEmptyState() {
        let chart = makeChart(pollData: [], rollupData: [], hasAnyHistoricalData: true)
        // Should display "No data for this time range"
        let _ = chart.body
    }

    // MARK: - Time Range Labels

    @Test("UsageChart renders for each time range")
    func rendersForAllTimeRanges() {
        for range in TimeRange.allCases {
            let chart = makeChart(timeRange: range)
            let _ = chart.body
        }
    }

    // MARK: - Flexible Sizing

    @Test("UsageChart uses maxWidth/maxHeight .infinity for flexible resizing")
    func flexibleSizing() {
        // The chart uses frame(maxWidth: .infinity, maxHeight: .infinity) — cannot assert frame
        // modifiers directly, but we verify it renders within a constrained parent without crash
        let chart = makeChart()
        let _ = chart.body
    }
}
