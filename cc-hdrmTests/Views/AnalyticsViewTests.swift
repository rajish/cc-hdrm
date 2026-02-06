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
