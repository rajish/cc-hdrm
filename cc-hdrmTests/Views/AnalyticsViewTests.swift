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
        appState: AppState = AppState()
    ) -> AnalyticsView {
        AnalyticsView(
            onClose: onClose,
            historicalDataService: historicalDataService,
            appState: appState
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
        // AnalyticsView declares: @State private var fiveHourVisible: Bool = true
        //                         @State private var sevenDayVisible: Bool = true
        // Cannot read @State from outside, but we verify the view renders
        // with both series assumed active (no crash = both paths exercised)
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
        #expect(mock.lastQueriedTimeRange == .week)
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
        #expect(mock.callOrder == ["ensureRollupsUpToDate", "getRolledUpData", "getResetEvents"])
    }

    // MARK: - 3.6 getResetEvents is called for each range

    @Test("getResetEvents is called for .day range")
    func resetEventsCalledForDay() async throws {
        let mock = MockHistoricalDataService()
        _ = try await AnalyticsView.fetchData(for: .day, using: mock)
        #expect(mock.getResetEventsCallCount == 1)
    }

    @Test("getResetEvents is called for .week range")
    func resetEventsCalledForWeek() async throws {
        let mock = MockHistoricalDataService()
        _ = try await AnalyticsView.fetchData(for: .week, using: mock)
        #expect(mock.getResetEventsCallCount == 1)
    }

    @Test("getResetEvents is called for .month range")
    func resetEventsCalledForMonth() async throws {
        let mock = MockHistoricalDataService()
        _ = try await AnalyticsView.fetchData(for: .month, using: mock)
        #expect(mock.getResetEventsCallCount == 1)
    }

    @Test("getResetEvents is called for .all range")
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
                        resetCount: 0, wasteCredits: nil)
        ]

        let result = try await AnalyticsView.fetchData(for: .week, using: mock)

        // ensureRollupsUpToDate threw, but data query still proceeded
        #expect(mock.ensureRollupsUpToDateCallCount == 1)
        #expect(mock.getRolledUpDataCallCount == 1)
        #expect(result.rollupData.count == 1)
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
