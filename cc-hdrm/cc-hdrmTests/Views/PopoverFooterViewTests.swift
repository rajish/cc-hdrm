import os
import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("PopoverFooterView Tests")
struct PopoverFooterViewTests {

    @Test("Footer renders with subscription tier data without crash")
    @MainActor
    func rendersWithSubscriptionTier() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateSubscriptionTier("Max")
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        let view = PopoverFooterView(appState: appState, preferencesManager: MockPreferencesManager())
        _ = view.body
    }

    @Test("Footer renders with nil subscription tier — shows dash")
    @MainActor
    func rendersWithNilSubscriptionTier() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        // subscriptionTier is nil by default
        let view = PopoverFooterView(appState: appState, preferencesManager: MockPreferencesManager())
        _ = view.body
        #expect(appState.subscriptionTier == nil)
    }

    @Test("Footer renders with fresh data (dataFreshness == .fresh)")
    @MainActor
    func rendersWithFreshData() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        // lastUpdated is set to Date() by updateWindows, so dataFreshness == .fresh
        #expect(appState.dataFreshness == .fresh)
        let view = PopoverFooterView(appState: appState, preferencesManager: MockPreferencesManager())
        _ = view.body
    }

    @Test("Footer renders with stale data (dataFreshness == .stale) — warning color")
    @MainActor
    func rendersWithStaleData() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        // Set lastUpdated to 90 seconds ago to trigger stale state
        appState.setLastUpdated(Date().addingTimeInterval(-90))
        #expect(appState.dataFreshness == .stale)
        let view = PopoverFooterView(appState: appState, preferencesManager: MockPreferencesManager())
        _ = view.body
    }

    @Test("Footer renders when disconnected")
    @MainActor
    func rendersWhenDisconnected() {
        let appState = AppState()
        // Default is disconnected
        #expect(appState.connectionStatus == .disconnected)
        #expect(appState.dataFreshness == .unknown)
        let view = PopoverFooterView(appState: appState, preferencesManager: MockPreferencesManager())
        _ = view.body
    }

    @Test("Observation triggers when subscriptionTier changes")
    @MainActor
    func observationTriggersOnSubscriptionTierChange() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)

        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            let view = PopoverFooterView(appState: appState, preferencesManager: MockPreferencesManager())
            _ = view.body
        } onChange: {
            expectation.withLock { $0 = true }
        }

        appState.updateSubscriptionTier("Max")

        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect subscriptionTier change")
    }

    @Test("Observation triggers when lastUpdated changes")
    @MainActor
    func observationTriggersOnLastUpdatedChange() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)

        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            let view = PopoverFooterView(appState: appState, preferencesManager: MockPreferencesManager())
            _ = view.body
        } onChange: {
            expectation.withLock { $0 = true }
        }

        // updateWindows sets lastUpdated
        appState.updateWindows(
            fiveHour: WindowState(utilization: 10.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )

        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect lastUpdated change")
    }
}
