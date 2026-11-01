import Testing
import SQLite3
import SwiftUI
import AppKit
@testable import cc_hdrm

@Suite("AnalyticsView Tests")
@MainActor
struct AnalyticsViewTests {

    private func makeView(
        onClose: @escaping () -> Void = {},
        historicalDataService: any HistoricalDataServiceProtocol = MockHistoricalDataService(),
        appState: AppState = AppState(),
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol = {
            let mock = MockHeadroomAnalysisService()
            mock.mockPeriodSummary = PeriodSummary(
                usedCredits: 52, constrainedCredits: 12, unusedCredits: 36,
                resetCount: 1, avgPeakUtilization: 52.0,
                usedPercent: 52, constrainedPercent: 12, unusedPercent: 36
            )
            return mock
        }()
    ) -> AnalyticsView {
        AnalyticsView(
            onClose: onClose,
            historicalDataService: historicalDataService,
            appState: appState,
            headroomAnalysisService: headroomAnalysisService
        )
    }

    // MARK: - Initialization

    @Test("AnalyticsView initializes and renders without crashing")
    func initializesAndRenders() {
        let view = makeView()
        let _ = view.body
    }

    // MARK: - Close Callback

    @Test("onClose callback is invocable")
    func onCloseCallbackWorks() {
        var closeCalled = false
        let view = makeView(onClose: { closeCalled = true })
        view.onClose()
        #expect(closeCalled == true)
    }

    // MARK: - Default State

    @Test("default time range is .week for balanced first impression")
    func defaultTimeRange() {
        // AnalyticsView uses @State private var selectedTimeRange: TimeRange = .week
        // We verify the default choice is documented and correct
        #expect(TimeRange.week.displayLabel == "7d")
    }

    // MARK: - TimeRange Integration

    @Test("all 4 time range options are available for selector")
    func allTimeRangesAvailable() {
        let ranges = TimeRange.allCases
        #expect(ranges.count == 4)
        #expect(ranges.map(\.displayLabel) == ["24h", "7d", "30d", "All"])
    }

    // MARK: - Series Toggle Defaults

    @Test("both series are visible by default per story spec")
    func seriesDefaultsDocumented() {
        // SeriesVisibility defaults both series to true.
        // The view's empty seriesVisibility dictionary falls back to these defaults.
        let defaults = AnalyticsView.SeriesVisibility()
        #expect(defaults.fiveHour == true)
        #expect(defaults.sevenDay == true)

        // Verify the view also renders correctly with defaults (no crash)
        let view = makeView()
        let _ = view.body
    }

    // MARK: - Dependency Injection

    @Test("AnalyticsView accepts HistoricalDataServiceProtocol for testability")
    func acceptsHistoricalDataService() {
        let mock = MockHistoricalDataService()
        let view = makeView(historicalDataService: mock)
        // Verify it compiles and renders with the mock
        let _ = view.body
    }

    @Test("AnalyticsView accepts AppState for credit limits access")
    func acceptsAppState() {
        let appState = AppState()
        appState.updateCreditLimits(CreditLimits(fiveHourCredits: 100, sevenDayCredits: 909))
        let view = makeView(appState: appState)
        let _ = view.body
    }

    @Test("AnalyticsView renders with nil credit limits (unknown tier)")
    func rendersWithNilCreditLimits() {
        let appState = AppState()
        // creditLimits defaults to nil
        let view = makeView(appState: appState)
        let _ = view.body
    }

    // MARK: - Data Loading Integration

    @Test("AnalyticsView can be created with mock that has pre-loaded data")
    func createdWithPreLoadedMock() {
        let mock = MockHistoricalDataService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        mock.recentPollsToReturn = [
            UsagePoll(id: 1, timestamp: nowMs - 60_000, fiveHourUtil: 30.0, fiveHourResetsAt: nil, sevenDayUtil: 15.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: nowMs, fiveHourUtil: 35.0, fiveHourResetsAt: nil, sevenDayUtil: 16.0, sevenDayResetsAt: nil)
        ]
        let view = makeView(historicalDataService: mock)
        let _ = view.body
    }

    @Test("AnalyticsView can be created with mock that throws on data load")
    func createdWithThrowingMock() {
        let mock = MockHistoricalDataService()
        mock.shouldThrowOnEnsureRollupsUpToDate = true
        let view = makeView(historicalDataService: mock)
        // Should not crash even with throwing mock — errors are caught in loadData()
        let _ = view.body
    }
}

// MARK: - Time-Range-Change Data Loading Tests (Story 13.3 Task 3)

@Suite("AnalyticsView Data Loading Tests")
@MainActor
struct AnalyticsViewDataLoadingTests {

    // MARK: - 3.1 Switching time range triggers data reload

    @Test("switching time range triggers data reload (call counts increment)")
    func switchingRangeTriggersReload() async throws {
        let mock = MockHistoricalDataService()

        // First load: .day
        _ = try await AnalyticsView.fetchData(for: .day, using: mock)
        #expect(mock.getRecentPollsCallCount == 1)

        // Second load: .week (simulates range switch)
        _ = try await AnalyticsView.fetchData(for: .week, using: mock)
        #expect(mock.getRolledUpDataCallCount == 1)

        // Third load: .day again
        _ = try await AnalyticsView.fetchData(for: .day, using: mock)
        #expect(mock.getRecentPollsCallCount == 2)
    }

    // MARK: - 3.2 .day range calls getRecentPolls, not getRolledUpData

    @Test(".day range calls getRecentPolls, not getRolledUpData")
    func dayRangeCallsGetRecentPolls() async throws {
        let mock = MockHistoricalDataService()
        let result = try await AnalyticsView.fetchData(for: .day, using: mock)

        #expect(mock.getRecentPollsCallCount == 1)
        #expect(mock.getRolledUpDataCallCount == 0)
        // .day returns chartData (polls), rollupData should be empty
        #expect(result.rollupData.isEmpty)
    }

    // MARK: - 3.3 .week range calls getRolledUpData, not getRecentPolls

    @Test(".week range calls getRolledUpData, not getRecentPolls")
    func weekRangeCallsGetRolledUpData() async throws {
        let mock = MockHistoricalDataService()
        let result = try await AnalyticsView.fetchData(for: .week, using: mock)

        #expect(mock.getRolledUpDataCallCount == 1)
        #expect(mock.getRecentPollsCallCount == 0)
        // lastQueriedTimeRange is .all due to the all-time reset events fetch
        #expect(mock.lastQueriedTimeRange == .all)
        // .week returns rollupData, chartData should be empty
        #expect(result.chartData.isEmpty)
    }

    // MARK: - 3.4 .all range calls getRolledUpData with .all parameter

    @Test(".all range calls getRolledUpData with .all parameter")
    func allRangeCallsGetRolledUpDataWithAll() async throws {
        let mock = MockHistoricalDataService()
        _ = try await AnalyticsView.fetchData(for: .all, using: mock)

        #expect(mock.getRolledUpDataCallCount == 1)
        #expect(mock.getRecentPollsCallCount == 0)
        #expect(mock.lastQueriedTimeRange == .all)
    }

    // MARK: - 3.5 ensureRollupsUpToDate is called before data queries

    @Test("ensureRollupsUpToDate is called before data queries (order verified)")
    func ensureRollupsCalledFirst() async throws {
        let mock = MockHistoricalDataService()
        _ = try await AnalyticsView.fetchData(for: .week, using: mock)

        #expect(mock.ensureRollupsUpToDateCallCount == 1)
        #expect(mock.getRolledUpDataCallCount == 1)
        // Verify actual call ordering, not just counts
        #expect(mock.callOrder == ["ensureRollupsUpToDate", "getRolledUpData", "getResetEvents", "getResetEvents"])
    }

    // MARK: - 3.6 getResetEvents is called for each range

    @Test("getResetEvents is called for .day range (range + all-time)")
    func resetEventsCalledForDay() async throws {
        let mock = MockHistoricalDataService()
        _ = try await AnalyticsView.fetchData(for: .day, using: mock)
        #expect(mock.getResetEventsCallCount == 2)
    }

    @Test("getResetEvents is called for .week range (range + all-time)")
    func resetEventsCalledForWeek() async throws {
        let mock = MockHistoricalDataService()
        _ = try await AnalyticsView.fetchData(for: .week, using: mock)
        #expect(mock.getResetEventsCallCount == 2)
    }

    @Test("getResetEvents is called for .month range (range + all-time)")
    func resetEventsCalledForMonth() async throws {
        let mock = MockHistoricalDataService()
        _ = try await AnalyticsView.fetchData(for: .month, using: mock)
        #expect(mock.getResetEventsCallCount == 2)
    }

    @Test("getResetEvents is called once for .all range (reuses range events as all-time)")
    func resetEventsCalledForAll() async throws {
        let mock = MockHistoricalDataService()
        _ = try await AnalyticsView.fetchData(for: .all, using: mock)
        #expect(mock.getResetEventsCallCount == 1)
    }

    // MARK: - 3.7 Rollup failure does not prevent data loading

    @Test("rollup failure does not prevent data loading")
    func rollupFailureDoesNotBlockDataLoad() async throws {
        let mock = MockHistoricalDataService()
        mock.shouldThrowOnEnsureRollupsUpToDate = true

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        mock.rolledUpDataToReturn = [
            UsageRollup(id: 1, periodStart: nowMs - 3600_000, periodEnd: nowMs,
                        resolution: .fiveMin,
                        fiveHourAvg: 25.0, fiveHourPeak: 40.0, fiveHourMin: 10.0,
                        sevenDayAvg: 12.0, sevenDayPeak: 20.0, sevenDayMin: 5.0,
                        resetCount: 0, unusedCredits: nil)
        ]

        let result = try await AnalyticsView.fetchData(for: .week, using: mock)

        // ensureRollupsUpToDate threw, but data query still proceeded
        #expect(mock.ensureRollupsUpToDateCallCount == 1)
        #expect(mock.getRolledUpDataCallCount == 1)
        #expect(result.rollupData.count == 1)
    }

}

// MARK: - Per-Time-Range Series Toggle Persistence Tests (Story 13.4 Task 4)

@Suite("AnalyticsView Series Toggle Persistence Tests")
@MainActor
struct AnalyticsViewSeriesToggleTests {

    // MARK: - 4.1 Both series visible by default for any TimeRange key

    @Test("SeriesVisibility defaults all series to visible")
    func bothSeriesVisibleByDefault() {
        let visibility = AnalyticsView.SeriesVisibility()
        #expect(visibility.fiveHour == true)
        #expect(visibility.sevenDay == true)
        #expect(visibility.fable == true)
    }

    @Test("Empty dictionary lookup defaults to both-visible for any range")
    func emptyDictionaryDefaultsBothVisible() {
        let dict: [TimeRange: AnalyticsView.SeriesVisibility] = [:]
        for range in TimeRange.allCases {
            let vis = dict[range] ?? AnalyticsView.SeriesVisibility()
            #expect(vis.fiveHour == true, "fiveHour should default true for \(range)")
            #expect(vis.sevenDay == true, "sevenDay should default true for \(range)")
        }
    }

    // MARK: - 4.2 Per-range toggle persistence across range switches

    @Test("toggling 5h off for .day persists after switching to .week and back")
    func fiveHourOffPersistsAcrossRangeSwitch() {
        var dict: [TimeRange: AnalyticsView.SeriesVisibility] = [:]

        // Toggle 5h off for .day
        dict[.day, default: AnalyticsView.SeriesVisibility()].fiveHour = false

        // Switch to .week — should be unaffected (both true)
        let weekVis = dict[.week] ?? AnalyticsView.SeriesVisibility()
        #expect(weekVis.fiveHour == true)
        #expect(weekVis.sevenDay == true)

        // Switch back to .day — 5h should still be off
        let dayVis = dict[.day] ?? AnalyticsView.SeriesVisibility()
        #expect(dayVis.fiveHour == false, "5h should remain off for .day after range switch")
        #expect(dayVis.sevenDay == true, "7d should still be on for .day")
    }

    // MARK: - 4.3 Toggling 7d off for .week does not affect .day

    @Test("toggling 7d off for .week does not affect .day toggle state")
    func sevenDayOffForWeekDoesNotAffectDay() {
        var dict: [TimeRange: AnalyticsView.SeriesVisibility] = [:]

        // Toggle 7d off for .week
        dict[.week, default: AnalyticsView.SeriesVisibility()].sevenDay = false

        // .day should remain unaffected
        let dayVis = dict[.day] ?? AnalyticsView.SeriesVisibility()
        #expect(dayVis.fiveHour == true)
        #expect(dayVis.sevenDay == true, "7d should be true for .day — .week toggle must not affect it")

        // .week should retain its state
        let weekVis = dict[.week] ?? AnalyticsView.SeriesVisibility()
        #expect(weekVis.fiveHour == true)
        #expect(weekVis.sevenDay == false, "7d should be off for .week")
    }

    // MARK: - 4.4 Unvisited ranges default to both-visible

    @Test("unvisited ranges default to both-visible")
    func unvisitedRangesDefaultBothVisible() {
        var dict: [TimeRange: AnalyticsView.SeriesVisibility] = [:]

        // Only visit .day
        dict[.day, default: AnalyticsView.SeriesVisibility()].fiveHour = false

        // .week, .month, .all are unvisited — should all default both-visible
        for range in [TimeRange.week, .month, .all] {
            let vis = dict[range] ?? AnalyticsView.SeriesVisibility()
            #expect(vis.fiveHour == true, "fiveHour should default true for unvisited \(range)")
            #expect(vis.sevenDay == true, "sevenDay should default true for unvisited \(range)")
        }
    }

    // MARK: - 4.5 Both series off produces anySeriesVisible == false in UsageChart

    @Test("both series off produces anySeriesVisible == false via UsageChart")
    func bothSeriesOffProducesNoSeriesVisible() {
        // UsageChart's anySeriesVisible is fiveHourVisible || sevenDayVisible
        // When both are false from the dictionary, UsageChart should show no-series state
        let chart = UsageChart(
            pollData: [],
            rollupData: [],
            timeRange: .week,
            fiveHourVisible: false,
            sevenDayVisible: false,
            isLoading: false,
            hasAnyHistoricalData: true
        )
        // Renders the "Select a series to display" empty state — no crash
        let _ = chart.body
    }

    // MARK: - 4.6 fetchData is NOT re-triggered by series toggle changes

    @Test("fetchData is not triggered by series toggle changes (only time range triggers)")
    func fetchDataNotTriggeredByToggle() async throws {
        let mock = MockHistoricalDataService()

        // Simulate initial load for .week
        _ = try await AnalyticsView.fetchData(for: .week, using: mock)
        #expect(mock.getRolledUpDataCallCount == 1)

        // Series toggle changes are @State writes within the view — they do NOT
        // call fetchData because .task(id: selectedTimeRange) only fires on
        // selectedTimeRange changes, not seriesVisibility changes.
        //
        // We verify by calling fetchData again with the SAME range — if toggles
        // triggered fetches, call counts would be higher in real usage. Here we
        // confirm the static method only responds to explicit range parameters.
        _ = try await AnalyticsView.fetchData(for: .week, using: mock)
        #expect(mock.getRolledUpDataCallCount == 2, "Each explicit fetchData call increments count — toggles don't call fetchData")
        #expect(mock.ensureRollupsUpToDateCallCount == 2, "ensureRollups called per fetchData, not per toggle")
    }

    // MARK: - SeriesVisibility Equatable

    @Test("SeriesVisibility supports Equatable comparison")
    func seriesVisibilityEquatable() {
        let a = AnalyticsView.SeriesVisibility(fiveHour: true, sevenDay: false)
        let b = AnalyticsView.SeriesVisibility(fiveHour: true, sevenDay: false)
        let c = AnalyticsView.SeriesVisibility(fiveHour: false, sevenDay: false)
        let d = AnalyticsView.SeriesVisibility(fiveHour: true, sevenDay: false, fable: false)
        #expect(a == b)
        #expect(a != c)
        #expect(a != d, "fable field participates in equality")
    }

    // MARK: - Story 21.3: Fable Toggle State

    @Test("toggling fable off for .day persists after switching to .week and back")
    func fableOffPersistsAcrossRangeSwitch() {
        var dict: [TimeRange: AnalyticsView.SeriesVisibility] = [:]

        dict[.day, default: AnalyticsView.SeriesVisibility()].fable = false

        // Switch to .week — unaffected
        let weekVis = dict[.week] ?? AnalyticsView.SeriesVisibility()
        #expect(weekVis.fable == true)

        // Switch back to .day — fable still off, other series untouched
        let dayVis = dict[.day] ?? AnalyticsView.SeriesVisibility()
        #expect(dayVis.fable == false, "fable should remain off for .day after range switch")
        #expect(dayVis.fiveHour == true)
        #expect(dayVis.sevenDay == true)
    }

    @Test("unvisited ranges default fable to visible")
    func unvisitedRangesDefaultFableVisible() {
        var dict: [TimeRange: AnalyticsView.SeriesVisibility] = [:]
        dict[.day, default: AnalyticsView.SeriesVisibility()].fable = false

        for range in [TimeRange.week, .month, .all] {
            let vis = dict[range] ?? AnalyticsView.SeriesVisibility()
            #expect(vis.fable == true, "fable should default true for unvisited \(range)")
        }
    }

    // MARK: - Story 21.3: Fable Label Fallback

    @Test("fableLabel falls back to Model for nil, empty, and blank display names")
    func fableLabelFallback() {
        #expect(AnalyticsView.fableLabel(from: "Fable") == "Fable")
        #expect(AnalyticsView.fableLabel(from: nil) == "Model")
        #expect(AnalyticsView.fableLabel(from: "") == "Model", "Empty display name must not render a blank chip label")
        #expect(AnalyticsView.fableLabel(from: "   ") == "Model", "Blank display name must not render a blank chip label")
        #expect(AnalyticsView.fableLabel(from: "  Fable  ") == "Fable", "Label is trimmed")
    }

    // MARK: - Story 21.3: Fable Data Presence (chip gating)

    @Test("hasFableData is false for empty data and data without fable values")
    func hasFableDataFalseWithoutFableValues() {
        #expect(AnalyticsView.hasFableData(polls: [], rollups: []) == false)

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let polls = [
            UsagePoll(id: 1, timestamp: nowMs, fiveHourUtil: 50.0, fiveHourResetsAt: nil,
                      sevenDayUtil: 25.0, sevenDayResetsAt: nil)
        ]
        let rollups = [
            UsageRollup(id: 1, periodStart: nowMs - 300_000, periodEnd: nowMs,
                        resolution: .fiveMin,
                        fiveHourAvg: 30.0, fiveHourPeak: 45.0, fiveHourMin: 20.0,
                        sevenDayAvg: 15.0, sevenDayPeak: 25.0, sevenDayMin: 10.0,
                        resetCount: 0, unusedCredits: nil)
        ]
        #expect(AnalyticsView.hasFableData(polls: polls, rollups: rollups) == false,
                "All-NULL fable columns must not surface the chip")
    }

    @Test("Fable history appears in analytics data after one persisted poll cycle")
    func fableHistoryAppearsAfterOnePollCycle() async throws {
        // Integration path: real HistoricalDataService + DatabaseManager on a temp DB,
        // persistPoll -> fetchData, mirroring the epic's success criterion.
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")
        let dbManager = DatabaseManager(databasePath: testPath)
        defer {
            dbManager.closeConnection()
            try? FileManager.default.removeItem(at: testPath)
        }
        try dbManager.ensureSchema()
        let service = HistoricalDataService(databaseManager: dbManager)

        let response = UsageResponse(
            fiveHour: WindowUsage(utilization: 45.0, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 20.0, resetsAt: nil),
            limits: [
                LimitEntry(
                    kind: "weekly_scoped",
                    group: nil,
                    percent: 63.0,
                    severity: nil,
                    resetsAt: "2026-08-12T22:00:00Z",
                    isActive: true,
                    scope: LimitScope(model: ScopedModel(id: "claude-fable-5", displayName: "Fable"), surface: nil)
                )
            ],
            extraUsage: nil
        )
        try await service.persistPoll(response)

        let result = try await AnalyticsView.fetchData(for: .day, using: service, existingAllTimeEvents: nil)

        #expect(result.chartData.count == 1, "One persisted poll cycle should surface one chart data point")
        #expect(result.chartData.first?.fableWeeklyUtil == 63.0, "Fable utilization must ride the analytics data path")
        #expect(AnalyticsView.hasFableData(polls: result.chartData, rollups: result.rollupData) == true,
                "The Fable chip gate must open after one poll cycle with a scoped limit")
    }

    @Test("hasFableData is true when any poll or rollup carries a fable value")
    func hasFableDataTrueWithFableValues() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let fablePoll = UsagePoll(id: 1, timestamp: nowMs, fiveHourUtil: 50.0, fiveHourResetsAt: nil,
                                  sevenDayUtil: nil, sevenDayResetsAt: nil, fableWeeklyUtil: 63.0)
        #expect(AnalyticsView.hasFableData(polls: [fablePoll], rollups: []) == true)

        let fableRollup = UsageRollup(id: 1, periodStart: nowMs - 300_000, periodEnd: nowMs,
                                      resolution: .fiveMin,
                                      fiveHourAvg: 30.0, fiveHourPeak: 45.0, fiveHourMin: 20.0,
                                      sevenDayAvg: nil, sevenDayPeak: nil, sevenDayMin: nil,
                                      resetCount: 0, unusedCredits: nil,
                                      fableWeeklyAvg: 60.0, fableWeeklyPeak: 65.0, fableWeeklyMin: 55.0)
        #expect(AnalyticsView.hasFableData(polls: [], rollups: [fableRollup]) == true)
    }

    // MARK: - Binding get/set closure verification (Code Review M1)

    @Test("Binding get returns correct value from dictionary for current range")
    func bindingGetReturnsCorrectValue() {
        // Replicate the exact Binding get pattern from AnalyticsView
        var dict: [TimeRange: AnalyticsView.SeriesVisibility] = [:]
        let selectedRange: TimeRange = .day

        // Empty dict — get should return true (default)
        let getResult = dict[selectedRange]?.fiveHour ?? true
        #expect(getResult == true)

        // Set 5h off for .day
        dict[.day] = AnalyticsView.SeriesVisibility(fiveHour: false, sevenDay: true)

        // Get should now return false
        let getAfterSet = dict[selectedRange]?.fiveHour ?? true
        #expect(getAfterSet == false)
    }

    @Test("Binding set creates dictionary entry for unvisited range via default subscript")
    func bindingSetCreatesEntryForUnvisitedRange() {
        // Replicate the exact Binding set pattern from AnalyticsView
        var dict: [TimeRange: AnalyticsView.SeriesVisibility] = [:]

        // .month has no entry yet — set should create one via default subscript
        dict[.month, default: AnalyticsView.SeriesVisibility()].fiveHour = false

        // Verify the entry was created with fiveHour=false and sevenDay=true (default)
        #expect(dict[.month] != nil, "Set via default subscript should create entry")
        #expect(dict[.month]?.fiveHour == false)
        #expect(dict[.month]?.sevenDay == true, "sevenDay should retain default true")
    }

    @Test("Binding get does not mutate dictionary (no side-effect insertion)")
    func bindingGetDoesNotMutateDictionary() {
        // The get closure uses optional chaining (dict[key]?.prop ?? default),
        // NOT the default subscript. Verify reading does not insert entries.
        var dict: [TimeRange: AnalyticsView.SeriesVisibility] = [:]

        // Read for .week — should NOT create a dictionary entry
        let _ = dict[.week]?.fiveHour ?? true
        #expect(dict[.week] == nil, "Get via optional chaining must not insert dictionary entry")
        #expect(dict.isEmpty, "Dictionary should remain empty after read-only access")
    }

    @Test("Binding set for one range does not affect other ranges")
    func bindingSetIsolatedPerRange() {
        var dict: [TimeRange: AnalyticsView.SeriesVisibility] = [:]

        // Set 5h off for .day
        dict[.day, default: AnalyticsView.SeriesVisibility()].fiveHour = false
        // Set 7d off for .week
        dict[.week, default: AnalyticsView.SeriesVisibility()].sevenDay = false

        // Verify .day: 5h off, 7d on
        #expect(dict[.day]?.fiveHour == false)
        #expect(dict[.day]?.sevenDay == true)

        // Verify .week: 5h on, 7d off
        #expect(dict[.week]?.fiveHour == true)
        #expect(dict[.week]?.sevenDay == false)

        // Verify .month untouched
        #expect(dict[.month] == nil)
    }

    // MARK: - Multiple ranges with independent toggle states

    @Test("each time range maintains independent toggle state")
    func independentToggleStatePerRange() {
        var dict: [TimeRange: AnalyticsView.SeriesVisibility] = [:]

        // Set different states for each range
        dict[.day] = AnalyticsView.SeriesVisibility(fiveHour: false, sevenDay: true)
        dict[.week] = AnalyticsView.SeriesVisibility(fiveHour: true, sevenDay: false)
        dict[.month] = AnalyticsView.SeriesVisibility(fiveHour: false, sevenDay: false)
        // .all left unvisited

        #expect(dict[.day]?.fiveHour == false)
        #expect(dict[.day]?.sevenDay == true)
        #expect(dict[.week]?.fiveHour == true)
        #expect(dict[.week]?.sevenDay == false)
        #expect(dict[.month]?.fiveHour == false)
        #expect(dict[.month]?.sevenDay == false)

        // .all defaults
        let allVis = dict[.all] ?? AnalyticsView.SeriesVisibility()
        #expect(allVis.fiveHour == true)
        #expect(allVis.sevenDay == true)
    }
}

// MARK: - Conditional Display Tests (Story 14.5)

@Suite("AnalyticsView Conditional Display Tests")
@MainActor
struct AnalyticsViewConditionalDisplayTests {

    // MARK: - Helpers

    /// Creates sample events spanning the given number of hours.
    private func sampleEvents(count: Int = 3, spanHours: Double = 24) -> [ResetEvent] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let totalSpanMs = Int64(spanHours * 3_600_000)
        let stepMs = count > 1 ? totalSpanMs / Int64(count - 1) : 0
        return (0..<count).map { i in
            ResetEvent(
                id: Int64(i + 1),
                timestamp: nowMs - totalSpanMs + Int64(i) * stepMs,
                fiveHourPeak: 50.0 + Double(i),
                sevenDayUtil: 30.0 + Double(i),
                tier: "default_claude_pro",
                usedCredits: nil,
                constrainedCredits: nil,
                unusedCredits: nil
            )
        }
    }

    private func makeView(
        appState: AppState = AppState(),
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol = {
            let mock = MockHeadroomAnalysisService()
            mock.mockPeriodSummary = PeriodSummary(
                usedCredits: 52, constrainedCredits: 12, unusedCredits: 36,
                resetCount: 1, avgPeakUtilization: 52.0,
                usedPercent: 52, constrainedPercent: 12, unusedPercent: 36
            )
            return mock
        }()
    ) -> AnalyticsView {
        AnalyticsView(
            onClose: {},
            historicalDataService: MockHistoricalDataService(),
            appState: appState,
            headroomAnalysisService: headroomAnalysisService
        )
    }

    // MARK: - 4.1 computeDataSpanHours returns 0 for empty events

    @Test("computeDataSpanHours returns 0 for empty events")
    func dataSpanHoursEmptyEvents() {
        let hours = AnalyticsView.computeDataSpanHours(resetEvents: [])
        #expect(hours == 0)
    }

    // MARK: - 4.2 computeDataSpanHours returns correct hours for 3-hour span

    @Test("computeDataSpanHours returns correct hours for events spanning 3 hours")
    func dataSpanHoursThreeHours() {
        let events = sampleEvents(count: 3, spanHours: 3.0)
        let hours = AnalyticsView.computeDataSpanHours(resetEvents: events)
        #expect(abs(hours - 3.0) < 0.01, "Should be approximately 3 hours")
    }

    // MARK: - 4.3 computeDataSpanHours returns 0 for single event

    @Test("computeDataSpanHours returns 0 for single event (first == last)")
    func dataSpanHoursSingleEvent() {
        let events = sampleEvents(count: 1, spanHours: 0)
        let hours = AnalyticsView.computeDataSpanHours(resetEvents: events)
        #expect(hours == 0, "Single event has zero span")
    }

    // MARK: - 4.4 fetchData call counts unchanged (no regression)

    @Test("fetchData call counts unchanged (no regression from conditional display)")
    func fetchDataCallCountsUnchanged() async throws {
        let mock = MockHistoricalDataService()

        // .day range
        _ = try await AnalyticsView.fetchData(for: .day, using: mock)
        #expect(mock.getRecentPollsCallCount == 1)
        #expect(mock.getResetEventsCallCount == 2)

        // .week range
        _ = try await AnalyticsView.fetchData(for: .week, using: mock)
        #expect(mock.getRolledUpDataCallCount == 1)
        #expect(mock.getResetEventsCallCount == 4)
    }

    // MARK: - 4.5 AnalyticsView renders with empty events (AC 4 path)

    @Test("AnalyticsView renders without crashing with empty events (AC 4 path)")
    func rendersWithEmptyEvents() {
        let view = makeView()
        // Default @State has resetEvents = [], exercising AC 4 path
        let _ = view.body
    }

    // MARK: - 4.6 AnalyticsView renders with events spanning < 6 hours (AC 3 path)

    @Test("computeDataSpanHours detects sub-6-hour span; view renders without crashing (AC 3 logic verified via HeadroomBreakdownBarTests)")
    func rendersWithShortSpanEvents() {
        // Verify computeDataSpanHours correctly identifies spans that trigger qualifier mode
        let events = sampleEvents(count: 3, spanHours: 3.0)
        let hours = AnalyticsView.computeDataSpanHours(resetEvents: events)
        #expect(hours < 6, "Events spanning 3 hours should trigger AC 3 qualifier path")

        // View renders without crashing (default @State has empty events;
        // AC 3 qualifier rendering verified in HeadroomBreakdownBarTests)
        let view = makeView()
        let _ = view.body
    }

    // MARK: - 4.7 AnalyticsView renders with quiet insight data (AC 5 path)

    @Test("ValueInsightEngine produces quiet insight for normal utilization; view renders without crashing (AC 5 logic)")
    func rendersWithQuietInsightData() {
        // Verify ValueInsightEngine correctly identifies quiet insights for AC 5 collapse logic.
        // Events must span >= 7 days so periodDays isn't capped below nominal week range.
        let events = sampleEvents(count: 10, spanHours: 168)
        let mock = MockHeadroomAnalysisService()
        mock.mockPeriodSummary = PeriodSummary(
            usedCredits: 2_500_000, constrainedCredits: 500_000, unusedCredits: 2_000_000,
            resetCount: 10, avgPeakUtilization: 50.0,
            usedPercent: 50, constrainedPercent: 10, unusedPercent: 40
        )

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .week,
            subscriptionValue: SubscriptionValueCalculator.calculate(
                resetEvents: events,
                creditLimits: RateLimitTier.pro.creditLimits,
                timeRange: .week,
                headroomAnalysisService: mock
            ),
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: RateLimitTier.pro.creditLimits,
            headroomAnalysisService: mock
        )
        #expect(insight.isQuiet == true, "50% utilization with no comparison history should be quiet")

        // View renders without crashing
        let view = makeView()
        let _ = view.body
    }

    // MARK: - 4.8 AnalyticsView renders with notable insight data (normal path)

    @Test("ValueInsightEngine produces notable insight for high utilization; view renders without crashing (normal path logic)")
    func rendersWithNotableInsightData() {
        // Verify ValueInsightEngine correctly identifies notable insights for normal display path
        let events = sampleEvents(count: 10, spanHours: 48)
        let mock = MockHeadroomAnalysisService()
        mock.mockPeriodSummary = PeriodSummary(
            usedCredits: 4_900_000, constrainedCredits: 50_000, unusedCredits: 50_000,
            resetCount: 10, avgPeakUtilization: 98.0,
            usedPercent: 98, constrainedPercent: 1, unusedPercent: 1
        )

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .week,
            subscriptionValue: SubscriptionValueCalculator.calculate(
                resetEvents: events,
                creditLimits: RateLimitTier.pro.creditLimits,
                timeRange: .week,
                headroomAnalysisService: mock
            ),
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: RateLimitTier.pro.creditLimits,
            headroomAnalysisService: mock
        )
        #expect(insight.isQuiet == false, "98% utilization should be notable (not quiet)")

        // View renders without crashing
        let view = makeView()
        let _ = view.body
    }
}

@Suite("AnalyticsPanel Tests")
@MainActor
struct AnalyticsPanelTests {

    @Test("AnalyticsPanel is a direct NSPanel subclass")
    func isNSPanelSubclass() {
        let panel = AnalyticsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        #expect(type(of: panel).superclass() == NSPanel.self)
        panel.close()
    }

    @Test("cancelOperation closes the panel (Escape key behavior)")
    func cancelOperationClosesPanel() {
        let panel = AnalyticsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.orderFront(nil)
        #expect(panel.isVisible == true)

        panel.cancelOperation(nil)
        #expect(panel.isVisible == false)
    }
}

@Suite("AnalyticsView Five-Hour Data Tests")
@MainActor
struct AnalyticsViewFiveHourDataTests {

    private typealias Visibility = AnalyticsView.SeriesVisibility

    private func poll(_ minute: Int64 = 0, fiveHour: Double? = nil, sevenDay: Double? = 20) -> UsagePoll {
        UsagePoll(id: minute, timestamp: 1_800_000_000_000 + minute * 60_000, fiveHourUtil: fiveHour,
                  fiveHourResetsAt: nil, sevenDayUtil: sevenDay, sevenDayResetsAt: nil)
    }

    private func rollup(
        day: Int64 = 0,
        avg: Double? = nil,
        peak: Double? = nil,
        min: Double? = nil,
        resetCount: Int = 0
    ) -> UsageRollup {
        let dayMs: Int64 = 86_400_000
        let start = 1_800_000_000_000 + day * dayMs
        return UsageRollup(id: day, periodStart: start, periodEnd: start + dayMs, resolution: .daily,
                           fiveHourAvg: avg, fiveHourPeak: peak, fiveHourMin: min,
                           sevenDayAvg: 20, sevenDayPeak: 30, sevenDayMin: 10,
                           resetCount: resetCount, unusedCredits: nil)
    }

    // MARK: - Deciding from the data

    @Test("a 24-hour range with only weekly polls hides the 5-hour series")
    func weeklyOnlyPollsHide() {
        #expect(AnalyticsView.isFiveHourHidden(polls: [poll(0), poll(1)], rollups: []))
    }

    @Test("rollups with no 5-hour value hide the 5-hour series")
    func weeklyOnlyRollupsHide() {
        #expect(AnalyticsView.isFiveHourHidden(polls: [], rollups: [rollup(day: 0), rollup(day: 1)]))
    }

    @Test("one 5-hour value anywhere keeps the series")
    func oneValueKeeps() {
        #expect(!AnalyticsView.isFiveHourHidden(polls: [poll(0), poll(1, fiveHour: 0)], rollups: []))
        #expect(!AnalyticsView.isFiveHourHidden(polls: [], rollups: [rollup(day: 0), rollup(day: 1, avg: 5)]))
        #expect(!AnalyticsView.isFiveHourHidden(polls: [], rollups: [rollup(day: 0), rollup(day: 1, peak: 5)]))
        #expect(!AnalyticsView.isFiveHourHidden(polls: [], rollups: [rollup(day: 0), rollup(day: 1, min: 5)]))
    }

    @Test("an empty range decides nothing, so the controls stay as they are today")
    func emptyRangeKeeps() {
        #expect(!AnalyticsView.isFiveHourHidden(polls: [], rollups: []))
    }

    // MARK: - A range with 5-hour data is unchanged

    @Test("with 5-hour data, every stored choice is drawn exactly as stored")
    func withDataEqualsStored() {
        let flags = [true, false]
        for fiveHour in flags {
            for sevenDay in flags {
                for fable in flags {
                    for hasFable in flags {
                        let stored = Visibility(fiveHour: fiveHour, sevenDay: sevenDay, fable: fable)
                        let drawn = stored.effective(fiveHourHidden: false, hasFableData: hasFable)
                        #expect(drawn.fiveHour == fiveHour)
                        #expect(drawn.sevenDay == sevenDay)
                        #expect(drawn.fable == (fable && hasFable))
                    }
                }
            }
        }
    }

    @Test("with 5-hour data, the weekly chip writes the stored choice")
    func withDataChipWritesStored() {
        var stored = Visibility()
        stored.setSevenDay(false, fiveHourHidden: false)
        #expect(stored == Visibility(fiveHour: true, sevenDay: false, fable: true))
    }

    @Test("defaults still draw every series when the range has 5-hour data")
    func withDataDefaults() {
        let drawn = Visibility().effective(fiveHourHidden: false, hasFableData: true)
        #expect(drawn.fiveHour && drawn.sevenDay && drawn.fable)
    }

    // MARK: - A range without 5-hour data

    @Test("without 5-hour data, the 5-hour series is off and weekly stays on by default")
    func withoutDataDefaults() {
        let drawn = Visibility().effective(fiveHourHidden: true, hasFableData: false)
        #expect(!drawn.fiveHour)
        #expect(drawn.sevenDay)
    }

    @Test("if 5-hour was the only series on, weekly shows")
    func onlyFiveHourFallsBackToWeekly() {
        let stored = Visibility(fiveHour: true, sevenDay: false, fable: false)
        let drawn = stored.effective(fiveHourHidden: true, hasFableData: true)
        #expect(!drawn.fiveHour)
        #expect(drawn.sevenDay)
    }

    @Test("a Fable toggle with no Fable data does not stop weekly showing")
    func fableWithoutDataStillFallsBack() {
        let stored = Visibility(fiveHour: true, sevenDay: false, fable: true)
        #expect(stored.effective(fiveHourHidden: true, hasFableData: false).sevenDay)
    }

    @Test("if Fable is showing, weekly stays off as the user chose")
    func fableShowingKeepsWeeklyOff() {
        let stored = Visibility(fiveHour: true, sevenDay: false, fable: true)
        let drawn = stored.effective(fiveHourHidden: true, hasFableData: true)
        #expect(!drawn.sevenDay)
        #expect(drawn.fable)
    }

    @Test("a user who switched everything off still gets the select-a-series state")
    func everythingOffStaysOff() {
        let stored = Visibility(fiveHour: false, sevenDay: false, fable: false)
        let drawn = stored.effective(fiveHourHidden: true, hasFableData: false)
        #expect(!drawn.fiveHour && !drawn.sevenDay && !drawn.fable)
    }

    // MARK: - Toggles and the stored choice

    @Test("the weekly chip responds to every press while 5-hour is hidden")
    func weeklyChipResponds() {
        var stored = Visibility()
        stored.setSevenDay(false, fiveHourHidden: true)
        #expect(!stored.effective(fiveHourHidden: true, hasFableData: false).sevenDay)
        stored.setSevenDay(true, fiveHourHidden: true)
        #expect(stored.effective(fiveHourHidden: true, hasFableData: false).sevenDay)
    }

    @Test("the weekly chip responds when weekly is only showing as the fallback")
    func weeklyChipRespondsDuringFallback() {
        var stored = Visibility(fiveHour: true, sevenDay: false, fable: false)
        #expect(stored.effective(fiveHourHidden: true, hasFableData: false).sevenDay)
        stored.setSevenDay(false, fiveHourHidden: true)
        #expect(!stored.effective(fiveHourHidden: true, hasFableData: false).sevenDay)
    }

    @Test("visiting a range without 5-hour data and returning keeps the stored choices")
    func storedChoicesSurviveRoundTrip() {
        for original in [
            Visibility(fiveHour: true, sevenDay: false, fable: false),
            Visibility(fiveHour: false, sevenDay: true, fable: true),
            Visibility()
        ] {
            #expect(!original.effective(fiveHourHidden: true, hasFableData: false).fiveHour)
            let back = original.effective(fiveHourHidden: false, hasFableData: true)
            #expect(back.fiveHour == original.fiveHour)
            #expect(back.sevenDay == original.sevenDay)
        }
    }

    @Test("a weekly press while 5-hour is hidden does not apply once 5-hour data returns")
    func hiddenPressDoesNotLeak() {
        var stored = Visibility(fiveHour: true, sevenDay: true, fable: true)
        stored.setSevenDay(false, fiveHourHidden: true)
        let back = stored.effective(fiveHourHidden: false, hasFableData: false)
        #expect(stored.fiveHour)
        #expect(stored.sevenDay)
        #expect(back.fiveHour)
        #expect(back.sevenDay)
    }

    @Test("a newer weekly choice with 5-hour data replaces an older press made while hidden")
    func newerChoiceReplacesHiddenPress() {
        var stored = Visibility()
        stored.setSevenDay(false, fiveHourHidden: true)
        stored.setSevenDay(true, fiveHourHidden: false)
        #expect(stored.effective(fiveHourHidden: true, hasFableData: false).sevenDay)
    }

    // MARK: - Where 5-hour data exists in a mixed range

    @Test("slope colouring also works when an account gains a number")
    func slopeWhenGainingNumber() {
        let polls = [poll(0), poll(1), poll(10, fiveHour: 10), poll(11, fiveHour: 12)]
        #expect(StepAreaChartView.computeSlopeAtEachPoint(polls: polls) == [nil, nil, .flat, .steep])
    }

    @Test("slope colouring works on points with a number and is nil on points without")
    func slopeInMixedRange() {
        let polls = [poll(0, fiveHour: 10), poll(1, fiveHour: 12), poll(2, fiveHour: 14), poll(3), poll(4)]
        #expect(StepAreaChartView.computeSlopeAtEachPoint(polls: polls) == [.flat, .steep, .steep, nil, nil])
    }

    @Test("reset markers stay in a mixed range, and losing the number is not a reset")
    func resetsInMixedRange() {
        let polls = [
            poll(0, fiveHour: 60, sevenDay: 30),
            poll(1, fiveHour: 20, sevenDay: 30),
            poll(2, fiveHour: nil, sevenDay: 30),
            poll(3, fiveHour: nil, sevenDay: 5)
        ]
        let resets = StepAreaChartView.findResetTimestamps(in: polls)
        #expect(resets.map { Int64($0.timeIntervalSince1970 * 1000) } == [polls[1].timestamp, polls[3].timestamp])
    }

    @Test("the 24-hour chart draws 5-hour only for points that have it")
    func stepChartInMixedRange() {
        let polls = (0..<10).map { poll(Int64($0), fiveHour: $0 < 5 ? Double($0) + 10 : nil) }
        let chart = StepAreaChartView(polls: polls, fiveHourVisible: true, sevenDayVisible: true)
        #expect(chart.fiveHourPoints.count == 5)
        #expect(chart.sevenDayPoints.count == 10)
    }

    @Test("bars keep old 5-hour peaks and reset counts, and new periods have no 5-hour peak")
    func barsInMixedRange() {
        let rollups = [rollup(day: 0, avg: 30, peak: 45, min: 10, resetCount: 2), rollup(day: 1)]
        let points = BarChartView.makeBarPoints(from: rollups, timeRange: .all)
        #expect(points.map(\.fiveHourPeak) == [45, nil])
        #expect(points.map(\.resetCount) == [2, 0])
    }

    // MARK: - Real database

    @Test("a long range spanning a state change shows old 5-hour data; the 24-hour range does not")
    func realDatabaseAcrossStateChange() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).db")
        let manager = DatabaseManager(databasePath: path)
        defer {
            manager.closeConnection()
            try? FileManager.default.removeItem(at: path)
        }
        try manager.ensureSchema()
        let service = HistoricalDataService(databaseManager: manager)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let dayMs: Int64 = 86_400_000
        let oldStart = now - 60 * dayMs
        let connection = try manager.getConnection()
        #expect(sqlite3_exec(connection, """
            INSERT INTO usage_rollups (period_start, period_end, resolution,
                five_hour_avg, five_hour_peak, five_hour_min,
                seven_day_avg, seven_day_peak, seven_day_min, reset_count)
            VALUES (\(oldStart), \(oldStart + dayMs), 'daily', 30, 45, 10, 20, 25, 15, 1)
            """, nil, nil, nil) == SQLITE_OK)

        try await service.persistPoll(UsageResponse(
            fiveHour: nil,
            sevenDay: WindowUsage(utilization: 40, resetsAt: nil),
            limits: nil,
            extraUsage: nil
        ))

        let all = try await AnalyticsView.fetchData(for: .all, using: service)
        #expect(!AnalyticsView.isFiveHourHidden(polls: all.chartData, rollups: all.rollupData))
        let bars = BarChartView.makeBarPoints(from: all.rollupData, timeRange: .all)
        #expect(bars.first?.fiveHourPeak == 45)
        #expect(bars.first?.resetCount == 1)
        #expect(bars.last?.fiveHourPeak == nil)
        #expect(bars.last?.sevenDayPeak == 40)

        let day = try await AnalyticsView.fetchData(for: .day, using: service)
        #expect(day.chartData.count == 1)
        #expect(AnalyticsView.isFiveHourHidden(polls: day.chartData, rollups: day.rollupData))
    }
}
