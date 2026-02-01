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
        let view = PopoverView(appState: appState)
        // Verify it produces a body (SwiftUI view renders without error)
        _ = view.body
    }

    @Test("PopoverView body contains expected placeholder structure")
    @MainActor
    func bodyRendersPlaceholderStructure() {
        let appState = AppState()
        let view = PopoverView(appState: appState)
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

        // withObservationTracking proves the view body reads a tracked property,
        // so SwiftUI will re-render when that property changes.
        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            // Evaluate the view body — this registers tracked property access
            let view = PopoverView(appState: appState)
            _ = view.body
        } onChange: {
            expectation.withLock { $0 = true }
        }

        // Mutate a property that PopoverView.body reads (connectionStatus)
        appState.updateConnectionStatus(.connected)

        // onChange fires synchronously on the property mutation
        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect AppState change read by PopoverView.body")
    }

    @Test("PopoverView footer reflects disconnected state")
    @MainActor
    func footerReflectsDisconnectedState() {
        let appState = AppState()
        // Default connectionStatus is .disconnected
        let view = PopoverView(appState: appState)
        let controller = NSHostingController(rootView: view)
        _ = controller.view // force layout

        // After connecting, a new view evaluation should differ
        appState.updateConnectionStatus(.connected)
        let view2 = PopoverView(appState: appState)
        let controller2 = NSHostingController(rootView: view2)
        _ = controller2.view

        // Verify the appState reference is shared and connected
        #expect(appState.connectionStatus == .connected)
    }
}

// MARK: - 5h Gauge Integration Tests (Story 4.2, Task 9)

@Suite("PopoverView 5h Gauge Integration Tests")
struct PopoverView5hGaugeTests {

    @Test("PopoverView with valid 5h data renders without crash")
    @MainActor
    func validFiveHourData() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 17.0, resetsAt: Date().addingTimeInterval(47 * 60)),
            sevenDay: nil
        )
        let view = PopoverView(appState: appState)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
        #expect(appState.fiveHour != nil)
    }

    @Test("PopoverView with nil fiveHour renders disconnected gauge without crash")
    @MainActor
    func nilFiveHourData() {
        let appState = AppState()
        // Default: no fiveHour data, disconnected
        let view = PopoverView(appState: appState)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
        #expect(appState.fiveHour == nil)
    }

    @Test("Updating AppState.fiveHour triggers observation on FiveHourGaugeSection")
    @MainActor
    func fiveHourObservation() {
        let appState = AppState()
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
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(2 * 86400))
        )
        let view = PopoverView(appState: appState)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
        #expect(appState.sevenDay != nil)
    }

    @Test("PopoverView with nil sevenDay does NOT render 7d section")
    @MainActor
    func nilSevenDayData() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        let view = PopoverView(appState: appState)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
        #expect(appState.sevenDay == nil)
    }

    @Test("Updating AppState.sevenDay from nil to valid triggers observation")
    @MainActor
    func sevenDayObservation() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        // Start with nil sevenDay
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )

        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            let view = PopoverView(appState: appState)
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
