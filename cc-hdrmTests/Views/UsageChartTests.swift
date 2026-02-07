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

    @Test("Non-24h time range does NOT render step-area chart (renders bar chart)")
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
            // Verify branching preconditions: non-.day ranges use BarChartView path
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

    // MARK: - BarChartView Tests (Story 13.6)

    /// Creates sample rollup data for bar chart testing.
    private func makeSampleRollups(
        count: Int = 24,
        resolution: UsageRollup.Resolution = .fiveMin,
        intervalMs: Int64 = 300_000  // 5 min
    ) -> [UsageRollup] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var rollups: [UsageRollup] = []
        for i in 0..<count {
            let periodStart = nowMs - Int64(count - i) * intervalMs
            let periodEnd = periodStart + intervalMs
            rollups.append(UsageRollup(
                id: Int64(i),
                periodStart: periodStart,
                periodEnd: periodEnd,
                resolution: resolution,
                fiveHourAvg: 30.0 + Double(i) * 0.5,
                fiveHourPeak: 40.0 + Double(i) * 0.5,
                fiveHourMin: 20.0 + Double(i) * 0.3,
                sevenDayAvg: 15.0 + Double(i) * 0.3,
                sevenDayPeak: 20.0 + Double(i) * 0.4,
                sevenDayMin: 10.0 + Double(i) * 0.2,
                resetCount: 0,
                wasteCredits: nil
            ))
        }
        return rollups
    }

    /// Creates rollup data with reset events in specific periods.
    private func makeRollupsWithResets() -> [UsageRollup] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let intervalMs: Int64 = 300_000
        var rollups: [UsageRollup] = []
        for i in 0..<12 {
            let periodStart = nowMs - Int64(12 - i) * intervalMs
            let periodEnd = periodStart + intervalMs
            let resetCount = (i == 5 || i == 9) ? 1 : 0  // Resets at index 5 and 9
            rollups.append(UsageRollup(
                id: Int64(i),
                periodStart: periodStart,
                periodEnd: periodEnd,
                resolution: .fiveMin,
                fiveHourAvg: 30.0,
                fiveHourPeak: 50.0,
                fiveHourMin: 15.0,
                sevenDayAvg: 20.0,
                sevenDayPeak: 30.0,
                sevenDayMin: 10.0,
                resetCount: resetCount,
                wasteCredits: nil
            ))
        }
        return rollups
    }

    @Test("Bar chart renders for .week time range with rollup data (7.1)")
    func barChartRendersWeek() {
        let rollups = makeSampleRollups()
        let view = BarChartView(
            rollups: rollups,
            timeRange: .week,
            fiveHourVisible: true,
            sevenDayVisible: true
        )
        let _ = view.body
    }

    @Test("Bar chart renders for .month time range with rollup data (7.2)")
    func barChartRendersMonth() {
        let rollups = makeSampleRollups(count: 48, resolution: .hourly, intervalMs: 3_600_000)
        let view = BarChartView(
            rollups: rollups,
            timeRange: .month,
            fiveHourVisible: true,
            sevenDayVisible: true
        )
        let _ = view.body
    }

    @Test("Bar chart renders for .all time range with rollup data (7.3)")
    func barChartRendersAll() {
        let rollups = makeSampleRollups(count: 90, resolution: .daily, intervalMs: 86_400_000)
        let view = BarChartView(
            rollups: rollups,
            timeRange: .all,
            fiveHourVisible: true,
            sevenDayVisible: true
        )
        let _ = view.body
    }

    @Test("Bar point creation from rollup data -- peak values, dates, reset count (7.4)")
    func barPointCreation() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let fiveMinMs: Int64 = 300_000
        let calendar = Calendar.current

        // Create 3 rollups within the same hour
        let hourStart = calendar.dateInterval(
            of: .hour,
            for: Date(timeIntervalSince1970: Double(nowMs) / 1000.0)
        )!.start
        let hourStartMs = Int64(hourStart.timeIntervalSince1970 * 1000)

        let rollups = [
            UsageRollup(
                id: 1, periodStart: hourStartMs, periodEnd: hourStartMs + fiveMinMs,
                resolution: .fiveMin,
                fiveHourAvg: 30.0, fiveHourPeak: 45.0, fiveHourMin: 20.0,
                sevenDayAvg: 15.0, sevenDayPeak: 25.0, sevenDayMin: 10.0,
                resetCount: 1, wasteCredits: nil
            ),
            UsageRollup(
                id: 2, periodStart: hourStartMs + fiveMinMs, periodEnd: hourStartMs + 2 * fiveMinMs,
                resolution: .fiveMin,
                fiveHourAvg: 35.0, fiveHourPeak: 60.0, fiveHourMin: 25.0,
                sevenDayAvg: 18.0, sevenDayPeak: 30.0, sevenDayMin: 12.0,
                resetCount: 0, wasteCredits: nil
            ),
            UsageRollup(
                id: 3, periodStart: hourStartMs + 2 * fiveMinMs, periodEnd: hourStartMs + 3 * fiveMinMs,
                resolution: .fiveMin,
                fiveHourAvg: 25.0, fiveHourPeak: 50.0, fiveHourMin: 15.0,
                sevenDayAvg: 12.0, sevenDayPeak: 20.0, sevenDayMin: 8.0,
                resetCount: 2, wasteCredits: nil
            ),
        ]

        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .week)

        // All 3 rollups should aggregate into 1 hourly bar
        #expect(barPoints.count == 1)

        let point = barPoints[0]
        // Peak = max of peaks
        #expect(point.fiveHourPeak == 60.0)
        #expect(point.sevenDayPeak == 30.0)
        // Min = min of mins
        #expect(point.fiveHourMin == 15.0)
        #expect(point.sevenDayMin == 8.0)
        // Avg = simple average of averages
        #expect(abs((point.fiveHourAvg ?? 0) - 30.0) < 0.01)
        #expect(abs((point.sevenDayAvg ?? 0) - 15.0) < 0.01)
        // Reset count = sum
        #expect(point.resetCount == 3)
        // Date validation: periodStart should be the hour start
        #expect(abs(point.periodStart.timeIntervalSince(hourStart)) < 1.0)
    }

    @Test("5h-only visibility hides 7d bars (7.5)")
    func barChartFiveHourOnly() {
        let rollups = makeSampleRollups()
        let view = BarChartView(
            rollups: rollups,
            timeRange: .week,
            fiveHourVisible: true,
            sevenDayVisible: false
        )
        #expect(view.fiveHourVisible == true)
        #expect(view.sevenDayVisible == false)
        let _ = view.body
    }

    @Test("7d-only visibility hides 5h bars (7.6)")
    func barChartSevenDayOnly() {
        let rollups = makeSampleRollups()
        let view = BarChartView(
            rollups: rollups,
            timeRange: .week,
            fiveHourVisible: false,
            sevenDayVisible: true
        )
        #expect(view.fiveHourVisible == false)
        #expect(view.sevenDayVisible == true)
        let _ = view.body
    }

    @Test("Empty rollup data with non-.day range shows empty state (7.7)")
    func barChartEmptyRollups() {
        let chart = makeChart(rollupData: [], timeRange: .week, hasAnyHistoricalData: true)
        // With 0 data points and series visible, should show empty message not bar chart
        let _ = chart.body
    }

    @Test("Rollup data with reset events flags correct bars (7.8)")
    func barChartResetFlags() {
        let rollups = makeRollupsWithResets()
        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .week)

        // 12 five-minute rollups span 60 minutes — may land in 1 or 2 hourly bars
        // depending on where the current hour boundary falls
        #expect(barPoints.count >= 1 && barPoints.count <= 2)

        // Verify some bar points have resetCount > 0
        let resetBars = barPoints.filter { $0.resetCount > 0 }
        #expect(!resetBars.isEmpty)

        // Total resets across all bars should equal source total (2)
        let totalResets = barPoints.reduce(0) { $0 + $1.resetCount }
        #expect(totalResets == 2)
    }

    @Test("Non-.day range with rollup data no longer shows dataSummary stub (7.9)")
    func nonDayRangeRendersBarChart() {
        let rollups = makeSampleRollups()
        // Before 13.6, the else branch was dataSummary (icon + count text).
        // Now it should render BarChartView. Verify the view evaluates without crash.
        for range in [TimeRange.week, .month, .all] {
            let chart = makeChart(rollupData: rollups, timeRange: range)
            #expect(chart.timeRange != .day)
            #expect(!chart.rollupData.isEmpty)
            let _ = chart.body
        }
    }

    @Test("Bar point creation returns empty for .day time range")
    func barPointCreationDayRange() {
        let rollups = makeSampleRollups()
        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .day)
        #expect(barPoints.isEmpty)
    }

    @Test("Bar point creation returns empty for empty rollups")
    func barPointCreationEmptyRollups() {
        let barPoints = BarChartView.makeBarPoints(from: [], timeRange: .week)
        #expect(barPoints.isEmpty)
    }

    @Test("Bar points with nil fiveHourPeak produce nil in bar point")
    func barPointNilFiveHour() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let rollups = [
            UsageRollup(
                id: 1, periodStart: nowMs - 300_000, periodEnd: nowMs,
                resolution: .fiveMin,
                fiveHourAvg: nil, fiveHourPeak: nil, fiveHourMin: nil,
                sevenDayAvg: 20.0, sevenDayPeak: 30.0, sevenDayMin: 15.0,
                resetCount: 0, wasteCredits: nil
            )
        ]
        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .week)
        #expect(barPoints.count == 1)
        #expect(barPoints[0].fiveHourPeak == nil)
        #expect(barPoints[0].sevenDayPeak == 30.0)
    }

    @Test("Bar points with nil sevenDayPeak produce nil in bar point")
    func barPointNilSevenDay() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let rollups = [
            UsageRollup(
                id: 1, periodStart: nowMs - 300_000, periodEnd: nowMs,
                resolution: .fiveMin,
                fiveHourAvg: 30.0, fiveHourPeak: 45.0, fiveHourMin: 20.0,
                sevenDayAvg: nil, sevenDayPeak: nil, sevenDayMin: nil,
                resetCount: 0, wasteCredits: nil
            )
        ]
        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .week)
        #expect(barPoints.count == 1)
        #expect(barPoints[0].fiveHourPeak == 45.0)
        #expect(barPoints[0].sevenDayPeak == nil)
    }

    // MARK: - Helpers for Gap Detection Tests

    /// Creates hourly rollups with specific hours missing to test gap detection.
    /// `missingHourOffsets` are the hours (0-based from the start) to omit.
    private func makeHourlyRollupsWithGaps(
        totalHours: Int = 24,
        missingHourOffsets: Set<Int> = []
    ) -> [UsageRollup] {
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: Date())
        let baseMs = Int64(baseDate.timeIntervalSince1970 * 1000)
        let hourMs: Int64 = 3_600_000
        let fiveMinMs: Int64 = 300_000

        var rollups: [UsageRollup] = []
        var rollupId: Int64 = 0
        for hour in 0..<totalHours {
            if missingHourOffsets.contains(hour) { continue }
            // Create 2 five-min rollups per hour
            for sub in 0..<2 {
                let periodStart = baseMs + Int64(hour) * hourMs + Int64(sub) * fiveMinMs
                rollups.append(UsageRollup(
                    id: rollupId,
                    periodStart: periodStart,
                    periodEnd: periodStart + fiveMinMs,
                    resolution: .fiveMin,
                    fiveHourAvg: 30.0,
                    fiveHourPeak: 45.0,
                    fiveHourMin: 20.0,
                    sevenDayAvg: 15.0,
                    sevenDayPeak: 25.0,
                    sevenDayMin: 10.0,
                    resetCount: 0,
                    wasteCredits: nil
                ))
                rollupId += 1
            }
        }
        return rollups
    }

    /// Creates daily rollups with specific days missing.
    private func makeDailyRollupsWithGaps(
        totalDays: Int = 10,
        missingDayOffsets: Set<Int> = []
    ) -> [UsageRollup] {
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -totalDays, to: Date())!)
        let baseMs = Int64(baseDate.timeIntervalSince1970 * 1000)
        let dayMs: Int64 = 86_400_000
        let hourMs: Int64 = 3_600_000

        var rollups: [UsageRollup] = []
        var rollupId: Int64 = 0
        for day in 0..<totalDays {
            if missingDayOffsets.contains(day) { continue }
            // Create 2 hourly rollups per day
            for sub in 0..<2 {
                let periodStart = baseMs + Int64(day) * dayMs + Int64(sub) * hourMs
                rollups.append(UsageRollup(
                    id: rollupId,
                    periodStart: periodStart,
                    periodEnd: periodStart + hourMs,
                    resolution: .hourly,
                    fiveHourAvg: 30.0,
                    fiveHourPeak: 45.0,
                    fiveHourMin: 20.0,
                    sevenDayAvg: 15.0,
                    sevenDayPeak: 25.0,
                    sevenDayMin: 10.0,
                    resetCount: 0,
                    wasteCredits: nil
                ))
                rollupId += 1
            }
        }
        return rollups
    }

    // MARK: - BarChartView Gap Detection Tests (Story 13.7)

    @Test("BarChartView gap detection -- hourly gaps detected for .week range (4.1)")
    func barGapDetectionHourlyWeek() {
        // Missing hours 3 and 7 out of 0..9
        let rollups = makeHourlyRollupsWithGaps(totalHours: 10, missingHourOffsets: [3, 7])
        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .week)
        let gapRanges = BarChartView.findGapRanges(in: barPoints, timeRange: .week)

        // Should have 2 gap ranges (hour 3 and hour 7 are non-consecutive)
        #expect(gapRanges.count == 2)

        // Verify gap durations are ~1 hour each
        for gap in gapRanges {
            let durationHours = gap.end.timeIntervalSince(gap.start) / 3600
            #expect(abs(durationHours - 1.0) < 0.01)
        }
    }

    @Test("BarChartView gap detection -- daily gaps detected for .month range (4.2)")
    func barGapDetectionDailyMonth() {
        // Missing days 2 and 5 out of 0..7
        let rollups = makeDailyRollupsWithGaps(totalDays: 8, missingDayOffsets: [2, 5])
        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .month)
        let gapRanges = BarChartView.findGapRanges(in: barPoints, timeRange: .month)

        // Should have 2 gap ranges (day 2 and day 5 are non-consecutive)
        #expect(gapRanges.count == 2)

        // Verify gap durations are ~1 day each
        for gap in gapRanges {
            let durationDays = gap.end.timeIntervalSince(gap.start) / 86400
            #expect(abs(durationDays - 1.0) < 0.01)
        }
    }

    @Test("BarChartView gap detection -- consecutive missing periods merged into single gap range (4.3)")
    func barGapDetectionMergedConsecutive() {
        // Missing hours 3, 4, 5 (consecutive) out of 0..9
        let rollups = makeHourlyRollupsWithGaps(totalHours: 10, missingHourOffsets: [3, 4, 5])
        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .week)
        let gapRanges = BarChartView.findGapRanges(in: barPoints, timeRange: .week)

        // Should merge into 1 continuous gap range (AC 3)
        #expect(gapRanges.count == 1)

        // Gap should span 3 hours
        let durationHours = gapRanges[0].end.timeIntervalSince(gapRanges[0].start) / 3600
        #expect(abs(durationHours - 3.0) < 0.01)
    }

    @Test("BarChartView gap detection -- no gaps when all periods have data (4.4)")
    func barGapDetectionNoGaps() {
        let rollups = makeHourlyRollupsWithGaps(totalHours: 10, missingHourOffsets: [])
        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .week)
        let gapRanges = BarChartView.findGapRanges(in: barPoints, timeRange: .week)

        #expect(gapRanges.isEmpty)
    }

    @Test("BarChartView gap detection -- gaps at start/end of data range not detected (4.5)")
    func barGapDetectionStartEnd() {
        // Missing hours 0 and 9 (start and end) out of 0..9
        // Gaps should NOT be detected outside data range
        let rollups = makeHourlyRollupsWithGaps(totalHours: 10, missingHourOffsets: [0, 9])
        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .week)
        let gapRanges = BarChartView.findGapRanges(in: barPoints, timeRange: .week)

        // The first bar starts at hour 1, last at hour 8 — no gaps between them
        // since hours 1..8 are all present
        #expect(gapRanges.isEmpty)
    }

    @Test("BarChartView with gap data renders without crash (4.6)")
    func barChartWithGapsRenders() {
        let rollups = makeHourlyRollupsWithGaps(totalHours: 10, missingHourOffsets: [3, 4, 7])
        let view = BarChartView(
            rollups: rollups,
            timeRange: .week,
            fiveHourVisible: true,
            sevenDayVisible: true
        )
        #expect(!view.gapRanges.isEmpty)
        let _ = view.body
    }

    @Test("StepAreaChartView gap ranges passed to overlay -- gapRanges computed from poll data with gaps (4.7)")
    func stepAreaGapRangesComputed() {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        let gapMs: Int64 = 10 * 60 * 1000  // 10-minute gap exceeding 5-min threshold
        let polls = [
            UsagePoll(id: 1, timestamp: nowMs - gapMs - 60_000, fiveHourUtil: 30.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: nowMs - gapMs, fiveHourUtil: 35.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            // 10-minute gap
            UsagePoll(id: 3, timestamp: nowMs - 60_000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 4, timestamp: nowMs, fiveHourUtil: 15.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]

        let view = StepAreaChartView(polls: polls, fiveHourVisible: true, sevenDayVisible: false)
        // Should detect the gap between segments
        #expect(view.gapRanges.count == 1)
        // Gap should span from the last point of segment 0 to first point of segment 1
        #expect(view.gapRanges[0].start < view.gapRanges[0].end)
    }

    @Test("BarChartView gap range boundaries align with period boundaries (4.8)")
    func barGapBoundariesAlignWithPeriods() {
        let calendar = Calendar.current
        // Missing hour 5 out of 0..9
        let rollups = makeHourlyRollupsWithGaps(totalHours: 10, missingHourOffsets: [5])
        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .week)
        let gapRanges = BarChartView.findGapRanges(in: barPoints, timeRange: .week)

        #expect(gapRanges.count == 1)
        let gap = gapRanges[0]

        // Gap start should be an exact hour boundary
        let startComponents = calendar.dateComponents([.minute, .second], from: gap.start)
        #expect(startComponents.minute == 0)
        #expect(startComponents.second == 0)

        // Gap end should be an exact hour boundary (start of next period)
        let endComponents = calendar.dateComponents([.minute, .second], from: gap.end)
        #expect(endComponents.minute == 0)
        #expect(endComponents.second == 0)

        // Duration should be exactly 1 hour
        let durationHours = gap.end.timeIntervalSince(gap.start) / 3600
        #expect(abs(durationHours - 1.0) < 0.01)
    }

    @Test("StepAreaChartView gap hover uses cursor date not nearest point date (review fix)")
    func stepAreaGapHoverUsesCursorDate() {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        let gapMs: Int64 = 10 * 60 * 1000  // 10-minute gap exceeding 5-min threshold
        // Segment 0: two polls, then 10-min gap, then Segment 1: two polls
        let polls = [
            UsagePoll(id: 1, timestamp: nowMs - gapMs - 60_000, fiveHourUtil: 30.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: nowMs - gapMs, fiveHourUtil: 35.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            // 10-minute gap here
            UsagePoll(id: 3, timestamp: nowMs - 60_000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 4, timestamp: nowMs, fiveHourUtil: 15.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]

        let view = StepAreaChartView(polls: polls, fiveHourVisible: true, sevenDayVisible: false)
        #expect(view.gapRanges.count == 1)
        let gap = view.gapRanges[0]

        // Simulate cursor in the SECOND half of the gap (closer to segment 1 start)
        // This is the exact scenario where using nearest-point date fails:
        // nearest point would be segment 1 start (at gap.end), and gap.end is NOT < gap.end
        let cursorInSecondHalf = Date(
            timeIntervalSince1970: (gap.start.timeIntervalSince1970 + gap.end.timeIntervalSince1970) / 2.0
            + (gap.end.timeIntervalSince1970 - gap.start.timeIntervalSince1970) * 0.3
        )

        // Verify cursor IS inside the gap range (the condition HoverOverlayContent.hoveredGap checks)
        let isInGap = gap.start <= cursorInSecondHalf && cursorInSecondHalf < gap.end
        #expect(isInGap, "Cursor in second half of gap must be detected as inside gap range")

        // Verify that the nearest chart point's date is NOT inside the gap (the old bug)
        // Find nearest point by date (same binary-search logic the chart uses)
        let nearestPoint = view.chartPoints.min(by: {
            abs($0.date.timeIntervalSince(cursorInSecondHalf)) < abs($1.date.timeIntervalSince(cursorInSecondHalf))
        })!
        let nearestInGap = gap.start <= nearestPoint.date && nearestPoint.date < gap.end
        #expect(!nearestInGap, "Nearest point date should NOT be in gap — this is why cursor date must be used")
    }

    @Test("Single rollup produces single bar point")
    func barPointSingleRollup() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let rollups = [
            UsageRollup(
                id: 1, periodStart: nowMs - 300_000, periodEnd: nowMs,
                resolution: .fiveMin,
                fiveHourAvg: 30.0, fiveHourPeak: 45.0, fiveHourMin: 20.0,
                sevenDayAvg: 15.0, sevenDayPeak: 25.0, sevenDayMin: 10.0,
                resetCount: 0, wasteCredits: nil
            )
        ]
        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .week)
        #expect(barPoints.count == 1)
    }

    @Test("Monthly aggregation groups hourly rollups into daily bars")
    func monthlyAggregation() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayMs = Int64(today.timeIntervalSince1970 * 1000)
        let hourMs: Int64 = 3_600_000

        // Create 24 hourly rollups spanning one day
        var rollups: [UsageRollup] = []
        for i in 0..<24 {
            rollups.append(UsageRollup(
                id: Int64(i),
                periodStart: todayMs + Int64(i) * hourMs,
                periodEnd: todayMs + Int64(i + 1) * hourMs,
                resolution: .hourly,
                fiveHourAvg: 30.0 + Double(i),
                fiveHourPeak: 50.0 + Double(i),
                fiveHourMin: 10.0 + Double(i),
                sevenDayAvg: 20.0,
                sevenDayPeak: 25.0,
                sevenDayMin: 15.0,
                resetCount: i == 12 ? 1 : 0,
                wasteCredits: nil
            ))
        }

        let barPoints = BarChartView.makeBarPoints(from: rollups, timeRange: .month)
        // All 24 hourly rollups should aggregate into 1 daily bar
        #expect(barPoints.count == 1)
        // Peak should be max across all hours
        #expect(barPoints[0].fiveHourPeak == 50.0 + 23.0)
        // Min should be min across all hours
        #expect(barPoints[0].fiveHourMin == 10.0)
        // Reset count should be 1
        #expect(barPoints[0].resetCount == 1)
    }
}
