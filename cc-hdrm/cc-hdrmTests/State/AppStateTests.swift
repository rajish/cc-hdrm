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
}
