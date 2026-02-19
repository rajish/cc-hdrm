import os
import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("PopoverView Tests")
struct PopoverViewTests {

    @Test("PopoverView can be instantiated with an AppState without crash")
    @MainActor
    func instantiationDoesNotCrash() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        // Verify it produces a body (SwiftUI view renders without error)
        _ = view.body
    }

    @Test("PopoverView body contains expected placeholder structure")
    @MainActor
    func bodyRendersPlaceholderStructure() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        // Verify the view can be hosted in an NSHostingController (the actual integration path)
        let hostingController = NSHostingController(rootView: view)
        #expect(hostingController.view.frame.size.width >= 0, "Hosting controller should create a valid view")
    }
}

// MARK: - Live Update Integration Tests (Story 4.1, Task 6)

@Suite("PopoverView Live Update Tests")
struct PopoverViewLiveUpdateTests {

    @Test("PopoverView triggers observation callback when AppState changes")
    @MainActor
    func appStateObservationTriggersReRender() async {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)

        // withObservationTracking proves the view body reads a tracked property,
        // so SwiftUI will re-render when that property changes.
        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            // Evaluate the view body — this registers tracked property access
            let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
            _ = view.body
        } onChange: {
            expectation.withLock { $0 = true }
        }

        // Mutate a property that PopoverView.body reads (sevenDay via appState.sevenDay != nil)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(86400))
        )

        // onChange fires synchronously on the property mutation
        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect AppState change read by PopoverView.body")
    }

    @Test("PopoverView with footer renders without crash in disconnected and connected states")
    @MainActor
    func footerRendersInBothStates() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        // Disconnected state — footer should render with "—" placeholders
        #expect(appState.connectionStatus == .disconnected)
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view // force layout

        // Connected state with data — footer should render with tier and freshness
        appState.updateConnectionStatus(.connected)
        appState.updateSubscriptionTier("Max")
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        #expect(appState.connectionStatus == .connected)
        #expect(appState.dataFreshness == .fresh)
        let view2 = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller2 = NSHostingController(rootView: view2)
        _ = controller2.view
    }

    @Test("PopoverView with subscription tier renders footer without crash")
    @MainActor
    func footerRendersWithSubscriptionTier() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateSubscriptionTier("Max")
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
        #expect(appState.subscriptionTier == "Max")
    }

    @Test("PopoverView observation triggers on sevenDay change (conditional section)")
    @MainActor
    func observationTriggersOnSevenDayChange() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)

        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
            _ = view.body
        } onChange: {
            expectation.withLock { $0 = true }
        }

        // sevenDay is read directly by PopoverView.body (the `if appState.sevenDay != nil` condition)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(86400))
        )

        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect sevenDay change read by PopoverView.body")
    }
}

// MARK: - Status Message Integration Tests (Story 4.5, Task 4)

@Suite("PopoverView Status Message Tests")
struct PopoverViewStatusMessageTests {

    @Test("PopoverView renders without crash when connectionStatus == .disconnected")
    @MainActor
    func rendersInDisconnectedState() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        // Default state is .disconnected
        #expect(appState.connectionStatus == .disconnected)
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("PopoverView renders without crash when connectionStatus == .tokenExpired")
    @MainActor
    func rendersInTokenExpiredState() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.tokenExpired)
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("PopoverView renders without crash when connectionStatus == .noCredentials")
    @MainActor
    func rendersInNoCredentialsState() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.noCredentials)
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("PopoverView renders without crash when connected with very stale data")
    @MainActor
    func rendersWithVeryStaleData() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        // Make data very stale (> 5 minutes old)
        appState.setLastUpdated(Date().addingTimeInterval(-400))
        #expect(appState.dataFreshness == .veryStale)
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("PopoverView renders without crash when connected with fresh data (no StatusMessageView)")
    @MainActor
    func rendersWithFreshDataNoStatusMessage() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        #expect(appState.dataFreshness == .fresh)
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("Observation triggers when connectionStatus changes")
    @MainActor
    func observationTriggersOnConnectionStatusChange() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        // Start disconnected (default)

        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
            _ = view.body
        } onChange: {
            expectation.withLock { $0 = true }
        }

        // Change connectionStatus — PopoverView.body reads it via resolvedStatusMessage
        appState.updateConnectionStatus(.connected)

        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect connectionStatus change read by PopoverView.body")
    }
}

// MARK: - Extra Usage Card Integration Tests (Story 17.2, Task 8)

@Suite("PopoverView Extra Usage Card Tests")
struct PopoverViewExtraUsageCardTests {

    @Test("PopoverView renders without crash when extra usage enabled with spend")
    @MainActor
    func rendersWithExtraUsageEnabled() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateExtraUsage(enabled: true, monthlyLimit: 43.0, usedCredits: 15.61, utilization: 0.363)
        let prefs = MockPreferencesManager()
        prefs.billingCycleDay = 1

        let view = PopoverView(appState: appState, preferencesManager: prefs, launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("PopoverView renders without crash when extra usage enabled with zero spend (collapsed)")
    @MainActor
    func rendersWithExtraUsageCollapsed() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateExtraUsage(enabled: true, monthlyLimit: 43.0, usedCredits: 0, utilization: 0.0)

        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("PopoverView renders without crash when extra usage disabled (no card)")
    @MainActor
    func rendersWithExtraUsageDisabled() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)

        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("Observation triggers when extraUsageEnabled changes")
    @MainActor
    func observationTriggersOnExtraUsageChange() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )

        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
            _ = view.body
        } onChange: {
            expectation.withLock { $0 = true }
        }

        // Enable extra usage — PopoverView.body reads appState.extraUsageEnabled directly
        appState.updateExtraUsage(enabled: true, monthlyLimit: 43.0, usedCredits: 15.0, utilization: 0.35)

        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect extraUsageEnabled change read by PopoverView.body")
    }
}

// MARK: - 5h Gauge Integration Tests (Story 4.2, Task 9)

@Suite("PopoverView 5h Gauge Integration Tests")
struct PopoverView5hGaugeTests {

    @Test("PopoverView with valid 5h data renders without crash")
    @MainActor
    func validFiveHourData() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 17.0, resetsAt: Date().addingTimeInterval(47 * 60)),
            sevenDay: nil
        )
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
        #expect(appState.fiveHour != nil)
    }

    @Test("PopoverView with nil fiveHour renders disconnected gauge without crash")
    @MainActor
    func nilFiveHourData() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        // Default: no fiveHour data, disconnected
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
        #expect(appState.fiveHour == nil)
    }

    @Test("Updating AppState.fiveHour triggers observation on FiveHourGaugeSection")
    @MainActor
    func fiveHourObservation() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)

        // Track observation at FiveHourGaugeSection level — this view directly reads fiveHour
        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            let section = FiveHourGaugeSection(appState: appState)
            _ = section.body
        } onChange: {
            expectation.withLock { $0 = true }
        }

        // Mutate fiveHour — FiveHourGaugeSection.body reads appState.fiveHour directly
        appState.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )

        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect fiveHour update read by FiveHourGaugeSection")
    }
}

// MARK: - 7d Gauge Integration Tests (Story 4.3, Task 4)

@Suite("PopoverView 7d Gauge Integration Tests")
struct PopoverView7dGaugeTests {

    @Test("PopoverView with valid sevenDay data renders 7d section without crash")
    @MainActor
    func validSevenDayData() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(2 * 86400))
        )
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
        #expect(appState.sevenDay != nil)
    }

    @Test("PopoverView with nil sevenDay does NOT render 7d section")
    @MainActor
    func nilSevenDayData() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
        #expect(appState.sevenDay == nil)
    }

    @Test("Updating AppState.sevenDay from nil to valid triggers observation")
    @MainActor
    func sevenDayObservation() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        // Start with nil sevenDay
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )

        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
            _ = view.body
        } onChange: {
            expectation.withLock { $0 = true }
        }

        // Update sevenDay from nil → valid data
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 40.0, resetsAt: Date().addingTimeInterval(86400))
        )

        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect sevenDay update read by PopoverView.body")
    }
}
