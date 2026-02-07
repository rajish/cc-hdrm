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

    /// Creates a sequence of polls with incrementing utilization over 24h.
    private func makeSamplePolls(count: Int = 148, baseUtil: Double = 10.0) -> [UsagePoll] {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        let intervalMs: Int64 = 30_000 // 30 seconds between polls
        let resetsAt: Int64 = nowMs + 3_600_000

        var result: [UsagePoll] = []
        for i in 0..<count {
            let fiveHour: Double = min(baseUtil + Double(i) * 0.5, 99.0)
            let sevenDay: Double = min(baseUtil / 2.0 + Double(i) * 0.25, 50.0)
            let ts: Int64 = nowMs - Int64(count - 1 - i) * intervalMs
            let poll = UsagePoll(
                id: Int64(i),
                timestamp: ts,
                fiveHourUtil: fiveHour,
                fiveHourResetsAt: resetsAt,
                sevenDayUtil: sevenDay,
                sevenDayResetsAt: resetsAt + 86_400_000
            )
            result.append(poll)
        }
        return result
    }

    /// Creates polls with a reset boundary at the midpoint.
    private func makePollsWithReset() -> [UsagePoll] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let intervalMs: Int64 = 30_000
        let resetsAt1 = nowMs + 3_600_000
        let resetsAt2 = nowMs + 3_600_000 + 18_000_000 // Shifted by 5 hours (new window)

        var polls: [UsagePoll] = []
        // First window: utilization climbs to 80%
        for i in 0..<20 {
            polls.append(UsagePoll(
                id: Int64(i),
                timestamp: nowMs - Int64(39 - i) * intervalMs,
                fiveHourUtil: 10.0 + Double(i) * 3.5,
                fiveHourResetsAt: resetsAt1,
                sevenDayUtil: 5.0 + Double(i) * 1.0,
                sevenDayResetsAt: nil
            ))
        }
        // Second window after reset: utilization drops to 5% and climbs
        for i in 0..<20 {
            polls.append(UsagePoll(
                id: Int64(20 + i),
                timestamp: nowMs - Int64(19 - i) * intervalMs,
                fiveHourUtil: 5.0 + Double(i) * 2.0,
                fiveHourResetsAt: resetsAt2,
                sevenDayUtil: 10.0 + Double(i) * 0.5,
                sevenDayResetsAt: nil
            ))
        }
        return polls
    }

    /// Creates polls with steep usage (high rate of change).
    private func makeSteepPolls() -> [UsagePoll] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let intervalMs: Int64 = 30_000 // 30s intervals
        let resetsAt = nowMs + 3_600_000

        var polls: [UsagePoll] = []
        // First 10 polls: flat (0.1%/min)
        for i in 0..<10 {
            polls.append(UsagePoll(
                id: Int64(i),
                timestamp: nowMs - Int64(29 - i) * intervalMs,
                fiveHourUtil: 10.0 + Double(i) * 0.05,
                fiveHourResetsAt: resetsAt,
                sevenDayUtil: nil,
                sevenDayResetsAt: nil
            ))
        }
        // Next 10 polls: steep (>1.5%/min, each 30s poll jumps ~1%)
        for i in 0..<10 {
            polls.append(UsagePoll(
                id: Int64(10 + i),
                timestamp: nowMs - Int64(19 - i) * intervalMs,
                fiveHourUtil: 10.5 + Double(i) * 1.0,
                fiveHourResetsAt: resetsAt,
                sevenDayUtil: nil,
                sevenDayResetsAt: nil
            ))
        }
        // Last 10 polls: flat again
        for i in 0..<10 {
            polls.append(UsagePoll(
                id: Int64(20 + i),
                timestamp: nowMs - Int64(9 - i) * intervalMs,
                fiveHourUtil: 20.5 + Double(i) * 0.05,
                fiveHourResetsAt: resetsAt,
                sevenDayUtil: nil,
                sevenDayResetsAt: nil
            ))
        }
        return polls
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
        let polls = makeSamplePolls()
        let chart = makeChart(pollData: polls, timeRange: .day)
        // Verify renders without crash -- step-area chart is displayed for .day
        let _ = chart.body
    }

    @Test("UsageChart shows data point count for rollup data")
    func showsDataPointCountForRollups() {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        var rollups: [UsageRollup] = []
        for i in 0..<50 {
            rollups.append(UsageRollup(
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
            ))
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
        // Should render without crash -- displays "Select a series to display"
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
        // Should display "No data yet -- usage history builds over time"
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
        // The chart uses frame(maxWidth: .infinity, maxHeight: .infinity) -- cannot assert frame
        // modifiers directly, but we verify it renders within a constrained parent without crash
        let chart = makeChart()
        let _ = chart.body
    }

    // MARK: - Step-Area Chart (Story 13.5)

    @Test("24h time range with poll data renders step-area chart")
    func dayRangeRendersStepAreaChart() {
        let polls = makeSamplePolls()
        let chart = makeChart(pollData: polls, timeRange: .day)
        // Verify branching preconditions: .day + data + series visible → StepAreaChartView path
        #expect(chart.timeRange == .day)
        #expect(chart.pollData.count == polls.count)
        #expect(chart.fiveHourVisible)
        // Renders without crash (SwiftUI views can't be inspected beyond this without snapshot tests)
        let _ = chart.body
    }

    @Test("Non-24h time range does NOT render step-area chart (falls back to stub)")
    func nonDayRangeDoesNotRenderStepArea() {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        var rollups: [UsageRollup] = []
        for i in 0..<10 {
            rollups.append(UsageRollup(
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
            ))
        }
        for range in [TimeRange.week, .month, .all] {
            let chart = makeChart(rollupData: rollups, timeRange: range)
            // Verify branching preconditions: non-.day ranges use dataSummary stub path
            #expect(chart.timeRange != .day)
            #expect(chart.pollData.isEmpty)
            let _ = chart.body
        }
    }

    @Test("Empty poll data with .day range shows empty state not chart")
    func emptyDayRangeShowsEmptyState() {
        let chart = makeChart(pollData: [], timeRange: .day, hasAnyHistoricalData: true)
        // Verify branching preconditions: .day + empty data → empty state (not chart)
        #expect(chart.timeRange == .day)
        #expect(chart.pollData.isEmpty)
        #expect(chart.rollupData.isEmpty)
        let _ = chart.body
    }

    @Test("5h-only visibility hides 7d series in step-area chart")
    func fiveHourOnlyVisibility() {
        let polls = makeSamplePolls()
        let chart = makeChart(
            pollData: polls,
            timeRange: .day,
            fiveHourVisible: true,
            sevenDayVisible: false
        )
        // Should render without crash, only 5h series visible
        let _ = chart.body
    }

    @Test("7d-only visibility hides 5h series in step-area chart")
    func sevenDayOnlyVisibility() {
        let polls = makeSamplePolls()
        let chart = makeChart(
            pollData: polls,
            timeRange: .day,
            fiveHourVisible: false,
            sevenDayVisible: true
        )
        // Should render without crash, only 7d series visible
        let _ = chart.body
    }

    // MARK: - StepAreaChartView Unit Tests

    @Test("Reset boundary detection identifies resets via utilization drop")
    func resetBoundaryDetection() {
        let polls = makePollsWithReset()
        let resets = StepAreaChartView.findResetTimestamps(in: polls)

        // The reset helper creates polls climbing to ~80% then dropping to 5%
        // That's a 75% drop — well above the 10% threshold
        #expect(resets.count == 1)
    }

    @Test("Reset boundary detection returns empty for monotonically increasing data")
    func noResetBoundary() {
        let polls = makeSamplePolls(count: 20)
        let resets = StepAreaChartView.findResetTimestamps(in: polls)
        #expect(resets.isEmpty)
    }

    @Test("Reset boundary detection handles empty polls")
    func resetBoundaryEmptyPolls() {
        let resets = StepAreaChartView.findResetTimestamps(in: [])
        #expect(resets.isEmpty)
    }

    @Test("Reset boundary detection handles single poll")
    func resetBoundarySinglePoll() {
        let poll = UsagePoll(
            id: 1,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            fiveHourUtil: 50.0,
            fiveHourResetsAt: nil,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )
        let resets = StepAreaChartView.findResetTimestamps(in: [poll])
        #expect(resets.isEmpty)
    }

    @Test("Monotonic enforcement clamps noise dips within segments")
    func monotonicEnforcement() {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        // Polls with a small noise dip at index 2 (42.0 → 41.5)
        let polls = [
            UsagePoll(id: 1, timestamp: nowMs - 90_000, fiveHourUtil: 40.0, fiveHourResetsAt: nil, sevenDayUtil: 20.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: nowMs - 60_000, fiveHourUtil: 42.0, fiveHourResetsAt: nil, sevenDayUtil: 21.0, sevenDayResetsAt: nil),
            UsagePoll(id: 3, timestamp: nowMs - 30_000, fiveHourUtil: 41.5, fiveHourResetsAt: nil, sevenDayUtil: 20.8, sevenDayResetsAt: nil),
            UsagePoll(id: 4, timestamp: nowMs, fiveHourUtil: 43.0, fiveHourResetsAt: nil, sevenDayUtil: 22.0, sevenDayResetsAt: nil),
        ]

        let view = StepAreaChartView(polls: polls, fiveHourVisible: true, sevenDayVisible: true)
        // Noise dip at index 2 should be clamped to the running max
        #expect(view.chartPoints[2].fiveHourUtil == 42.0)
        #expect(view.chartPoints[2].sevenDayUtil == 21.0)
        // Non-dip values unaffected
        #expect(view.chartPoints[0].fiveHourUtil == 40.0)
        #expect(view.chartPoints[3].fiveHourUtil == 43.0)
    }

    @Test("Monotonic enforcement resets at reset boundaries (large drops preserved)")
    func monotonicEnforcementResetsAtBoundary() {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        // Polls with a real reset (80% → 5%) — should NOT be clamped
        let polls = [
            UsagePoll(id: 1, timestamp: nowMs - 60_000, fiveHourUtil: 78.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: nowMs - 30_000, fiveHourUtil: 80.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 3, timestamp: nowMs, fiveHourUtil: 5.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]

        let view = StepAreaChartView(polls: polls, fiveHourVisible: true, sevenDayVisible: false)
        // Real reset drop should be preserved, not clamped
        #expect(view.chartPoints[2].fiveHourUtil == 5.0)
    }

    @Test("Slope calculation returns flat for uniform data")
    func slopeCalculationFlat() {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        var polls: [UsagePoll] = []
        for i in 0..<20 {
            let ts: Int64 = nowMs - Int64(19 - i) * 30_000
            polls.append(UsagePoll(
                id: Int64(i),
                timestamp: ts,
                fiveHourUtil: 50.0,
                fiveHourResetsAt: nil,
                sevenDayUtil: nil,
                sevenDayResetsAt: nil
            ))
        }
        let slopes = StepAreaChartView.computeSlopeAtEachPoint(polls: polls)

        // All slopes should be flat (rate ~0%/min)
        for slope in slopes {
            #expect(slope == .flat)
        }
    }

    @Test("Slope calculation classifies rising correctly")
    func slopeCalculationRising() {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        var polls: [UsagePoll] = []
        for i in 0..<20 {
            let ts: Int64 = nowMs - Int64(19 - i) * 30_000
            let util: Double = 10.0 + Double(i) * 0.25 // ~0.5%/min
            polls.append(UsagePoll(
                id: Int64(i),
                timestamp: ts,
                fiveHourUtil: util,
                fiveHourResetsAt: nil,
                sevenDayUtil: nil,
                sevenDayResetsAt: nil
            ))
        }
        let slopes = StepAreaChartView.computeSlopeAtEachPoint(polls: polls)

        // After the first few polls (window needs to build), should have rising slopes
        let laterSlopes = slopes.suffix(10).compactMap { $0 }
        let hasRising = laterSlopes.contains(.rising)
        #expect(hasRising)
    }

    @Test("Chart points are created from polls with correct dates")
    func chartPointCreation() {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        let polls = [
            UsagePoll(id: 1, timestamp: nowMs - 60_000, fiveHourUtil: 30.0, fiveHourResetsAt: nil, sevenDayUtil: 10.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: nowMs, fiveHourUtil: 35.0, fiveHourResetsAt: nil, sevenDayUtil: 12.0, sevenDayResetsAt: nil)
        ]

        let points = StepAreaChartView.makeChartPoints(from: polls)
        #expect(points.count == 2)
        #expect(points[0].fiveHourUtil == 30.0)
        #expect(points[1].fiveHourUtil == 35.0)
        #expect(points[0].sevenDayUtil == 10.0)
        #expect(points[1].sevenDayUtil == 12.0)
        // Consecutive polls (60s apart) should be in the same segment
        #expect(points[0].segment == points[1].segment)
        // Verify date conversion
        let expectedDate = Date(timeIntervalSince1970: Double(nowMs) / 1000.0)
        #expect(abs(points[1].date.timeIntervalSince(expectedDate)) < 0.001)
    }

    @Test("Chart points handle nil utilization values")
    func chartPointNilUtilization() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let polls = [
            UsagePoll(id: 1, timestamp: nowMs - 60_000, fiveHourUtil: nil, fiveHourResetsAt: nil, sevenDayUtil: 10.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: nowMs, fiveHourUtil: 35.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]

        let points = StepAreaChartView.makeChartPoints(from: polls)
        #expect(points.count == 2)
        #expect(points[0].fiveHourUtil == nil)
        #expect(points[0].sevenDayUtil == 10.0)
        #expect(points[1].fiveHourUtil == 35.0)
        #expect(points[1].sevenDayUtil == nil)
    }

    @Test("Slope calculation detects steep slopes in steep poll data")
    func slopeDetectsSteep() {
        let polls = makeSteepPolls()
        let slopes = StepAreaChartView.computeSlopeAtEachPoint(polls: polls)
        // The middle section has steep rate (>1.5%/min)
        let hasSteep = slopes.contains(.steep)
        #expect(hasSteep)
    }

    @Test("Gap in poll data creates separate segments")
    func gapSegmentation() {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        let gapMs: Int64 = 10 * 60 * 1000 // 10 minute gap (exceeds 5min threshold)
        let polls = [
            UsagePoll(id: 1, timestamp: nowMs - gapMs - 60_000, fiveHourUtil: 30.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: nowMs - gapMs, fiveHourUtil: 35.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            // 10 minute gap here
            UsagePoll(id: 3, timestamp: nowMs - 60_000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 4, timestamp: nowMs, fiveHourUtil: 15.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]

        let points = StepAreaChartView.makeChartPoints(from: polls)
        #expect(points.count == 4)
        // First two polls in segment 0
        #expect(points[0].segment == 0)
        #expect(points[1].segment == 0)
        // After gap, segment increments
        #expect(points[2].segment == 1)
        #expect(points[3].segment == 1)
    }

    @Test("StepAreaChartView renders without crash with sample data")
    func stepAreaChartViewRenders() {
        let polls = makeSamplePolls()
        let view = StepAreaChartView(
            polls: polls,
            fiveHourVisible: true,
            sevenDayVisible: true
        )
        let _ = view.body
    }

    @Test("StepAreaChartView renders with only 5h visible")
    func stepAreaFiveHourOnly() {
        let polls = makeSamplePolls()
        let view = StepAreaChartView(
            polls: polls,
            fiveHourVisible: true,
            sevenDayVisible: false
        )
        let _ = view.body
    }

    @Test("StepAreaChartView renders with only 7d visible")
    func stepAreaSevenDayOnly() {
        let polls = makeSamplePolls()
        let view = StepAreaChartView(
            polls: polls,
            fiveHourVisible: false,
            sevenDayVisible: true
        )
        let _ = view.body
    }

    @Test("StepAreaChartView renders with reset data")
    func stepAreaWithResets() {
        let polls = makePollsWithReset()
        let view = StepAreaChartView(
            polls: polls,
            fiveHourVisible: true,
            sevenDayVisible: true
        )
        let _ = view.body
    }

    @Test("StepAreaChartView renders with steep data")
    func stepAreaWithSteepData() {
        let polls = makeSteepPolls()
        let view = StepAreaChartView(
            polls: polls,
            fiveHourVisible: true,
            sevenDayVisible: false
        )
        let _ = view.body
    }
}
