import Foundation
import Testing
@testable import cc_hdrm

@Suite("AppState Tests")
struct AppStateTests {

    // MARK: - Default State Tests

    @Test("default connectionStatus is .disconnected")
    @MainActor
    func defaultConnectionStatus() {
        let state = AppState()
        #expect(state.connectionStatus == .disconnected)
    }

    @Test("default fiveHour is nil")
    @MainActor
    func defaultFiveHourIsNil() {
        let state = AppState()
        #expect(state.fiveHour == nil)
    }

    @Test("default sevenDay is nil")
    @MainActor
    func defaultSevenDayIsNil() {
        let state = AppState()
        #expect(state.sevenDay == nil)
    }

    @Test("default lastUpdated is nil")
    @MainActor
    func defaultLastUpdatedIsNil() {
        let state = AppState()
        #expect(state.lastUpdated == nil)
    }

    @Test("default subscriptionTier is nil")
    @MainActor
    func defaultSubscriptionTierIsNil() {
        let state = AppState()
        #expect(state.subscriptionTier == nil)
    }

    // MARK: - WindowState Derived HeadroomState Tests

    @Test("WindowState derives headroomState from utilization")
    func windowStateDeriveHeadroomState() {
        let window = WindowState(utilization: 83, resetsAt: nil)
        #expect(window.headroomState == .warning)
    }

    @Test("WindowState with low utilization derives .normal")
    func windowStateNormal() {
        let window = WindowState(utilization: 30, resetsAt: nil)
        #expect(window.headroomState == .normal)
    }

    @Test("WindowState with high utilization derives .critical")
    func windowStateCritical() {
        let window = WindowState(utilization: 97, resetsAt: nil)
        #expect(window.headroomState == .critical)
    }

    // MARK: - ConnectionStatus Enum Tests

    @Test("ConnectionStatus has all expected cases")
    func connectionStatusCases() {
        let cases: [ConnectionStatus] = [.connected, .disconnected, .tokenExpired, .noCredentials]
        #expect(cases.count == 4)
    }

    // MARK: - Mutation via Methods Tests

    @Test("updateWindows sets fiveHour and sevenDay and lastUpdated")
    @MainActor
    func updateWindowsSetsValues() {
        let state = AppState()
        let fiveHour = WindowState(utilization: 50, resetsAt: nil)
        let sevenDay = WindowState(utilization: 70, resetsAt: Date())

        state.updateWindows(fiveHour: fiveHour, sevenDay: sevenDay)

        #expect(state.fiveHour?.utilization == 50)
        #expect(state.sevenDay?.utilization == 70)
        #expect(state.lastUpdated != nil)
    }

    @Test("updateConnectionStatus changes status")
    @MainActor
    func updateConnectionStatusWorks() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        #expect(state.connectionStatus == .connected)
    }

    @Test("updateSubscriptionTier changes tier")
    @MainActor
    func updateSubscriptionTierWorks() {
        let state = AppState()
        state.updateSubscriptionTier("pro")
        #expect(state.subscriptionTier == "pro")
    }

    // MARK: - StatusMessage Tests

    @Test("default statusMessage is nil")
    @MainActor
    func defaultStatusMessageIsNil() {
        let state = AppState()
        #expect(state.statusMessage == nil)
    }

    @Test("updateStatusMessage sets title and detail")
    @MainActor
    func updateStatusMessageSetsValues() {
        let state = AppState()
        state.updateStatusMessage(StatusMessage(title: "No Claude credentials found", detail: "Run Claude Code to create them"))
        #expect(state.statusMessage == StatusMessage(title: "No Claude credentials found", detail: "Run Claude Code to create them"))
    }

    @Test("updateStatusMessage clears with nil")
    @MainActor
    func updateStatusMessageClearsWithNil() {
        let state = AppState()
        state.updateStatusMessage(StatusMessage(title: "title", detail: "detail"))
        state.updateStatusMessage(nil)
        #expect(state.statusMessage == nil)
    }

    // MARK: - DataFreshness Derived Property Tests

    @Test("dataFreshness returns .unknown when lastUpdated is nil")
    @MainActor
    func dataFreshnessUnknownWhenNilLastUpdated() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        #expect(state.dataFreshness == .unknown)
    }

    @Test("dataFreshness returns .fresh when lastUpdated is recent and connected")
    @MainActor
    func dataFreshnessFreshWhenRecentAndConnected() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 50, resetsAt: nil), sevenDay: nil)
        #expect(state.dataFreshness == .fresh)
    }

    @Test("dataFreshness returns .unknown when disconnected regardless of lastUpdated")
    @MainActor
    func dataFreshnessUnknownWhenDisconnected() {
        let state = AppState()
        // Update windows to set lastUpdated, then disconnect
        state.updateWindows(fiveHour: WindowState(utilization: 50, resetsAt: nil), sevenDay: nil)
        state.updateConnectionStatus(.disconnected)
        #expect(state.dataFreshness == .unknown)
    }

    @Test("dataFreshness returns .veryStale when lastUpdated is old and connected")
    @MainActor
    func dataFreshnessVeryStaleWhenOldAndConnected() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.setLastUpdated(Date().addingTimeInterval(-600))
        #expect(state.dataFreshness == .veryStale)
    }

    // MARK: - Menu Bar Headroom State Tests (Task 7)

    @Test("disconnected connectionStatus → menuBarHeadroomState == .disconnected and menuBarText == sparkle em dash")
    @MainActor
    func menuBarDisconnected() {
        let state = AppState()
        // Default connectionStatus is .disconnected
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2733} \u{2014}")
    }

    @Test("connected with nil fiveHour → .disconnected")
    @MainActor
    func menuBarConnectedNilFiveHour() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2733} \u{2014}")
    }

    @Test("connected with utilization 17.0 → headroom 83% → .normal")
    @MainActor
    func menuBarNormal83() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 17.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarHeadroomState == .normal)
        #expect(state.menuBarText == "\u{2733} 83%")
    }

    @Test("connected with utilization 65.0 → headroom 35% → .caution")
    @MainActor
    func menuBarCaution35() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 65.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarHeadroomState == .caution)
        #expect(state.menuBarText == "\u{2733} 35%")
    }

    @Test("connected with utilization 85.0 → headroom 15% → .warning")
    @MainActor
    func menuBarWarning15() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 85.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarHeadroomState == .warning)
        #expect(state.menuBarText == "\u{2733} 15%")
    }

    @Test("connected with utilization 97.0 → headroom 3% → .critical")
    @MainActor
    func menuBarCritical3() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 97.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarHeadroomState == .critical)
        #expect(state.menuBarText == "\u{2733} 3%")
    }

    @Test("connected with utilization 100.0 → headroom 0% → .exhausted")
    @MainActor
    func menuBarExhausted0() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 100.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarHeadroomState == .exhausted)
        #expect(state.menuBarText == "\u{2733} 0%")
    }

    @Test("tokenExpired → .disconnected")
    @MainActor
    func menuBarTokenExpired() {
        let state = AppState()
        state.updateConnectionStatus(.tokenExpired)
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2733} \u{2014}")
    }

    @Test("noCredentials → .disconnected")
    @MainActor
    func menuBarNoCredentials() {
        let state = AppState()
        state.updateConnectionStatus(.noCredentials)
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2733} \u{2014}")
    }

    @Test("utilization > 100 clamps headroom to 0%")
    @MainActor
    func menuBarUtilizationOver100() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 110.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarText == "\u{2733} 0%")
    }

    // MARK: - Headroom Percentage Edge Cases (Task 9)

    @Test("utilization 0.0 → headroom 100%")
    @MainActor
    func menuBarHeadroom100() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 0.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarText == "\u{2733} 100%")
    }

    @Test("utilization 50.5 → headroom 49% (Int truncation)")
    @MainActor
    func menuBarHeadroomTruncation() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 50.5, resetsAt: nil), sevenDay: nil)
        // Int(100 - 50.5) = Int(49.5) = 49
        #expect(state.menuBarText == "\u{2733} 49%")
    }

    @Test("utilization 99.9 → headroom 0% display (Int truncation) but .critical state (0.1% actual headroom)")
    @MainActor
    func menuBarHeadroom99_9() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 99.9, resetsAt: nil), sevenDay: nil)
        // Int(100 - 99.9) = Int(0.1) = 0 for display
        // But HeadroomState uses actual 0.1% headroom → 0<0.1<5 → .critical
        #expect(state.menuBarText == "\u{2733} 0%")
        #expect(state.menuBarHeadroomState == .critical)
    }
}
