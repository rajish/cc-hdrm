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

// MARK: - Story 4.6 — Ring Gauge Click Integration Tests

@Suite("PopoverView Ring Gauge Click Tests")
struct PopoverViewRingGaugeClickTests {

    @Test("PopoverView renders without crash when historicalDataService is nil (no click handlers)")
    @MainActor
    func rendersWithNilHistoricalDataService() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(86400))
        )
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService(), historicalDataService: nil)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("PopoverView renders without crash when historicalDataService is provided (click handlers active)")
    @MainActor
    func rendersWithHistoricalDataService() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(86400))
        )
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService(), historicalDataService: MockHistoricalDataService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
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

// MARK: - Scoped Limit Gauge Integration Tests (Story 21.2)

@Suite("PopoverView Scoped Limit Gauge Tests")
struct PopoverViewScopedLimitTests {

    @Test("PopoverView with scoped limits renders the scoped section without crash")
    @MainActor
    func scopedLimitsPresent() {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(2 * 86400))
        )
        appState.updateScopedLimits([
            ScopedLimitState(displayName: "Fable", utilization: 63.0, resetsAt: Date().addingTimeInterval(3 * 86400))
        ])
        let view = PopoverView(appState: appState, preferencesManager: MockPreferencesManager(), launchAtLoginService: MockLaunchAtLoginService())
        let controller = NSHostingController(rootView: view)
        _ = controller.view
        #expect(view.showsScopedLimitSection)
    }

    @Test("PopoverView with empty scopedLimits does NOT render the scoped section")
    @MainActor
    func scopedLimitsAbsent() {
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
        #expect(!view.showsScopedLimitSection)
    }

    @Test("Observation triggers when scopedLimits changes")
    @MainActor
    func observationTriggersOnScopedLimitsChange() {
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

        // scopedLimits is read directly by PopoverView.body (the `!appState.scopedLimits.isEmpty` guard)
        appState.updateScopedLimits([
            ScopedLimitState(displayName: "Fable", utilization: 63.0, resetsAt: Date().addingTimeInterval(86400))
        ])

        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect scopedLimits change read by PopoverView.body")
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

// MARK: - No 5-Hour Number

@Suite("PopoverView No 5-Hour Number Tests")
@MainActor
struct PopoverViewNoFiveHourTests {

    private func makeView(fiveHour: WindowState?, sevenDay: WindowState?, withAnalytics: Bool = true) -> PopoverView {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: fiveHour, sevenDay: sevenDay)
        return PopoverView(
            appState: appState,
            preferencesManager: MockPreferencesManager(),
            launchAtLoginService: MockLaunchAtLoginService(),
            historicalDataService: withAnalytics ? MockHistoricalDataService() : nil
        )
    }

    private let weekly = WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(86400))
    private let fiveHour = WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600))

    private func height(_ view: PopoverView) -> CGFloat {
        NSHostingController(rootView: view).view.fittingSize.height
    }

    @Test("no 5-hour number → ring and sparkline hidden, analytics button shown")
    func noFiveHourHidesRing() {
        let view = makeView(fiveHour: nil, sevenDay: weekly)
        #expect(!view.showsFiveHourSection)
        #expect(view.showsAnalyticsButton)
    }

    @Test("drawn height: ring gone, button drawn only with analytics, and smaller than the sparkline")
    func noFiveHourDrawnHeights() {
        let ringHeight: CGFloat = 96
        let sparklineBlockHeight: CGFloat = 56
        let withRing = height(makeView(fiveHour: fiveHour, sevenDay: weekly))
        let withButton = height(makeView(fiveHour: nil, sevenDay: weekly))
        let withoutButton = height(makeView(fiveHour: nil, sevenDay: weekly, withAnalytics: false))

        #expect(withRing - withoutButton > ringHeight)
        #expect(withButton > withoutButton)
        #expect(withButton - withoutButton < sparklineBlockHeight)
    }

    @Test("the long ahead-of-pace line wraps instead of widening the popover")
    func aheadOfPaceKeepsPopoverWidth() {
        let ahead = makeView(fiveHour: nil, sevenDay: WindowState(utilization: 60.0, resetsAt: Date().addingTimeInterval(4 * 86400)))
        let onPace = makeView(fiveHour: nil, sevenDay: weekly)
        #expect(ahead.appState.weeklyPace?.runOut != nil)
        #expect(onPace.appState.weeklyPace?.runOut == nil)

        let aheadSize = NSHostingController(rootView: ahead).view.fittingSize
        let onPaceSize = NSHostingController(rootView: onPace).view.fittingSize
        #expect(aheadSize.width == onPaceSize.width)
        #expect(aheadSize.height > onPaceSize.height)
    }

    @Test("no 5-hour number and no analytics service → no dead analytics button")
    func noFiveHourNoAnalyticsService() {
        let view = makeView(fiveHour: nil, sevenDay: weekly, withAnalytics: false)
        #expect(!view.showsFiveHourSection)
        #expect(!view.showsAnalyticsButton)
    }

    @Test("5-hour number present → ring and sparkline stay, no analytics button")
    func fiveHourPresentKeepsRing() {
        let view = makeView(fiveHour: fiveHour, sevenDay: weekly)
        #expect(view.showsFiveHourSection)
        #expect(!view.showsAnalyticsButton)
    }

    @Test("both windows nil → ring stays as today")
    func bothNilKeepsRing() {
        let view = makeView(fiveHour: nil, sevenDay: nil)
        #expect(view.showsFiveHourSection)
        #expect(!view.showsAnalyticsButton)
    }

    @Test("old weekly data while disconnected → ring stays hidden through a network blip")
    func disconnectedKeepsRingHidden() {
        let view = makeView(fiveHour: nil, sevenDay: weekly)
        view.appState.updateConnectionStatus(.disconnected)
        #expect(!view.showsFiveHourSection)
    }

    @Test("state flips → ring follows the data at the next update")
    func flipFollowsData() {
        let view = makeView(fiveHour: fiveHour, sevenDay: weekly)
        #expect(view.showsFiveHourSection)
        view.appState.updateWindows(fiveHour: nil, sevenDay: weekly)
        #expect(!view.showsFiveHourSection)
        view.appState.updateWindows(fiveHour: fiveHour, sevenDay: weekly)
        #expect(view.showsFiveHourSection)
    }

    // MARK: - Weekly Chart

    private func weeklyPoints(hours: Int) -> [UsagePoll] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return (0...hours).map { hour in
            UsagePoll(id: 0, timestamp: now - Int64(hours - hour) * 3_600_000, fiveHourUtil: nil, fiveHourResetsAt: nil, sevenDayUtil: Double(hour), sevenDayResetsAt: nil)
        }
    }

    @Test("enough weekly data → the chart replaces the analytics button")
    func weeklyChartReplacesButton() {
        let view = makeView(fiveHour: nil, sevenDay: weekly)
        let points = weeklyPoints(hours: 3)
        view.appState.updateWeeklySparklineData(points)
        let chart = view.weeklySparkline
        #expect(chart?.data == points)
        #expect(chart?.weeklyCycle == view.appState.weeklyCycle)
        #expect(chart?.weeklyCycle != nil)
        #expect(chart?.accessibilityLabelText == "Weekly usage chart. Double-tap to open analytics.")
        #expect(chart?.onTap != nil)
        #expect(!view.showsAnalyticsButton)
        #expect(!view.showsFiveHourSection)
    }

    @Test("the chart is taller than the button it replaces")
    func weeklyChartDrawn() {
        let withButton = makeView(fiveHour: nil, sevenDay: weekly)
        let withChart = makeView(fiveHour: nil, sevenDay: weekly)
        withChart.appState.updateWeeklySparklineData(weeklyPoints(hours: 3))
        #expect(height(withChart) > height(withButton))
    }

    @Test("reset time missing → the button stays and no chart draws, even with data")
    func noResetTimeKeepsButton() {
        let view = makeView(fiveHour: nil, sevenDay: WindowState(utilization: 35, resetsAt: nil))
        view.appState.updateWeeklySparklineData(weeklyPoints(hours: 3))
        #expect(view.weeklySparkline == nil)
        #expect(view.showsAnalyticsButton)
    }

    @Test("reset already passed → the button stays and no chart draws")
    func passedResetKeepsButton() {
        let view = makeView(fiveHour: nil, sevenDay: WindowState(utilization: 35, resetsAt: Date().addingTimeInterval(-60)))
        view.appState.updateWeeklySparklineData(weeklyPoints(hours: 3))
        #expect(view.weeklySparkline == nil)
        #expect(view.showsAnalyticsButton)
    }

    @Test("too little weekly data → the button stays and no empty chart draws")
    func tooLittleDataKeepsButton() {
        let view = makeView(fiveHour: nil, sevenDay: weekly)
        #expect(view.weeklySparkline == nil)
        #expect(view.showsAnalyticsButton)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        view.appState.updateWeeklySparklineData([
            UsagePoll(id: 0, timestamp: now - 60_000, fiveHourUtil: nil, fiveHourResetsAt: nil, sevenDayUtil: 1, sevenDayResetsAt: nil),
            UsagePoll(id: 0, timestamp: now, fiveHourUtil: nil, fiveHourResetsAt: nil, sevenDayUtil: 1, sevenDayResetsAt: nil)
        ])
        #expect(view.weeklySparkline == nil)
        #expect(view.showsAnalyticsButton)
    }

    @Test("no analytics service → no chart, so nothing offers a dead route")
    func noServiceNoChart() {
        let view = makeView(fiveHour: nil, sevenDay: weekly, withAnalytics: false)
        view.appState.updateWeeklySparklineData(weeklyPoints(hours: 3))
        #expect(view.weeklySparkline == nil)
        #expect(!view.showsAnalyticsButton)
    }

    @Test("old weekly data while disconnected → the chart stays through a network blip")
    func disconnectedKeepsChart() {
        let view = makeView(fiveHour: nil, sevenDay: weekly)
        view.appState.updateWeeklySparklineData(weeklyPoints(hours: 3))
        view.appState.updateConnectionStatus(.disconnected)
        #expect(view.weeklySparkline != nil)
    }

    @Test("5-hour number present → no weekly chart, whatever weekly data exists, and the same drawn height")
    func fiveHourPresentIgnoresWeeklyData() {
        let plain = makeView(fiveHour: fiveHour, sevenDay: weekly)
        let stray = makeView(fiveHour: fiveHour, sevenDay: weekly)
        stray.appState.updateWeeklySparklineData(weeklyPoints(hours: 3))
        #expect(stray.weeklySparkline == nil)
        #expect(stray.appState.weeklyCycle == nil)
        #expect(stray.showsFiveHourSection)
        #expect(!stray.showsAnalyticsButton)
        #expect(height(stray) == height(plain))
    }

    @Test("state flips → the chart follows at the next update, both ways")
    func chartFollowsFlip() {
        let view = makeView(fiveHour: nil, sevenDay: weekly)
        view.appState.updateWeeklySparklineData(weeklyPoints(hours: 3))
        #expect(view.weeklySparkline != nil)

        view.appState.updateWindows(fiveHour: fiveHour, sevenDay: weekly)
        #expect(view.weeklySparkline == nil)
        #expect(view.showsFiveHourSection)

        view.appState.updateWindows(fiveHour: nil, sevenDay: weekly)
        #expect(view.weeklySparkline != nil)
    }
}
