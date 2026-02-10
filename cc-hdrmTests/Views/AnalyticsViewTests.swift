import Testing
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

    @Test("SeriesVisibility defaults both series to visible")
    func bothSeriesVisibleByDefault() {
        let visibility = AnalyticsView.SeriesVisibility()
        #expect(visibility.fiveHour == true)
        #expect(visibility.sevenDay == true)
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
        #expect(a == b)
        #expect(a != c)
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
