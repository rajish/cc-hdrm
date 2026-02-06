import os
import SwiftUI
import Testing
@testable import cc_hdrm

// MARK: - PopoverView Sparkline Integration Tests (Story 12.4)

@Suite("PopoverView Sparkline Integration Tests")
@MainActor
struct PopoverViewSparklineTests {

    // MARK: - Task 1: Sparkline Section Presence (AC: 1, 4, 5)

    @Test("PopoverView renders without crash when sparklineData is empty")
    func rendersWithEmptySparklineData() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        // sparklineData is empty by default
        #expect(appState.sparklineData.isEmpty)

        let view = PopoverView(
            appState: appState,
            preferencesManager: MockPreferencesManager(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("PopoverView renders without crash with sparkline data")
    func rendersWithSparklineData() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )

        // Add test sparkline data
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let testPolls = [
            UsagePoll(id: 1, timestamp: now - 3600000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now, fiveHourUtil: 40.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(testPolls)
        #expect(appState.sparklineData.count == 2)

        let view = PopoverView(
            appState: appState,
            preferencesManager: MockPreferencesManager(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("PopoverView renders with both 5h and 7d gauges plus sparkline")
    func rendersWithBothGaugesAndSparkline() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(86400))
        )

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let testPolls = [
            UsagePoll(id: 1, timestamp: now - 3600000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now, fiveHourUtil: 40.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(testPolls)

        let view = PopoverView(
            appState: appState,
            preferencesManager: MockPreferencesManager(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
        let controller = NSHostingController(rootView: view)
        _ = controller.view

        #expect(appState.sevenDay != nil)
        #expect(appState.hasSparklineData)
    }

    // MARK: - Task 2: Sparkline Data Binding (AC: 1)

    @Test("Sparkline receives sparklineData from AppState")
    func sparklineReceivesData() {
        let appState = AppState()

        // Add some test data
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let testPolls = [
            UsagePoll(id: 1, timestamp: now - 3600000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now, fiveHourUtil: 40.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(testPolls)

        #expect(appState.sparklineData.count == 2)
        #expect(appState.hasSparklineData)
    }

    @Test("hasSparklineData returns false with fewer than 2 data points")
    func hasSparklineDataWithInsufficientData() {
        let appState = AppState()

        // No data
        #expect(appState.hasSparklineData == false)

        // Only one data point
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let onePoint = [
            UsagePoll(id: 1, timestamp: now, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(onePoint)
        #expect(appState.hasSparklineData == false)
    }

    // MARK: - Task 3: Analytics Window State Binding (AC: 2)

    @Test("isAnalyticsWindowOpen state is accessible from AppState")
    func analyticsWindowStateAccessible() {
        let appState = AppState()

        #expect(appState.isAnalyticsWindowOpen == false)
        appState.setAnalyticsWindowOpen(true)
        #expect(appState.isAnalyticsWindowOpen == true)
        appState.setAnalyticsWindowOpen(false)
        #expect(appState.isAnalyticsWindowOpen == false)
    }

    @Test("PopoverView renders correctly when analytics window is open")
    func rendersWithAnalyticsWindowOpen() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.setAnalyticsWindowOpen(true)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let testPolls = [
            UsagePoll(id: 1, timestamp: now - 3600000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now, fiveHourUtil: 40.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(testPolls)

        let view = PopoverView(
            appState: appState,
            preferencesManager: MockPreferencesManager(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
        let controller = NSHostingController(rootView: view)
        _ = controller.view

        #expect(appState.isAnalyticsWindowOpen == true)
    }

    // MARK: - Task 4: Observation Tracking

    @Test("Observation triggers when sparklineData changes")
    func observationTriggersOnSparklineDataChange() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )

        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            let view = PopoverView(
                appState: appState,
                preferencesManager: MockPreferencesManager(),
                launchAtLoginService: MockLaunchAtLoginService()
            )
            _ = view.body
        } onChange: {
            expectation.withLock { $0 = true }
        }

        // Update sparklineData
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let testPolls = [
            UsagePoll(id: 1, timestamp: now - 3600000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now, fiveHourUtil: 40.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(testPolls)

        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect sparklineData change read by PopoverView.body")
    }

    @Test("Observation triggers when isAnalyticsWindowOpen changes")
    func observationTriggersOnAnalyticsWindowOpenChange() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )

        // Add sparkline data so the sparkline renders (not placeholder)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let testPolls = [
            UsagePoll(id: 1, timestamp: now - 3600000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now, fiveHourUtil: 40.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(testPolls)

        let expectation = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            let view = PopoverView(
                appState: appState,
                preferencesManager: MockPreferencesManager(),
                launchAtLoginService: MockLaunchAtLoginService()
            )
            _ = view.body
        } onChange: {
            expectation.withLock { $0 = true }
        }

        // Change analytics window state
        appState.setAnalyticsWindowOpen(true)

        let detected = expectation.withLock { $0 }
        #expect(detected, "Observation should detect isAnalyticsWindowOpen change read by PopoverView.body")
    }

    // MARK: - Edge Cases (AC: 4)

    @Test("PopoverView renders placeholder when sparkline has insufficient data")
    func rendersPlaceholderWithInsufficientData() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )

        // Only one data point - should show placeholder
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let onePoint = [
            UsagePoll(id: 1, timestamp: now, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(onePoint)
        #expect(appState.hasSparklineData == false)

        let view = PopoverView(
            appState: appState,
            preferencesManager: MockPreferencesManager(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("PopoverView renders with StatusMessage and sparkline together")
    func rendersWithStatusMessageAndSparkline() {
        let appState = AppState()
        appState.updateConnectionStatus(.disconnected)  // Will show status message

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let testPolls = [
            UsagePoll(id: 1, timestamp: now - 3600000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now, fiveHourUtil: 40.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(testPolls)

        let view = PopoverView(
            appState: appState,
            preferencesManager: MockPreferencesManager(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
        let controller = NSHostingController(rootView: view)
        _ = controller.view

        // Disconnected state shows status message
        #expect(appState.connectionStatus == .disconnected)
    }

    @Test("PopoverView renders with UpdateBadge and sparkline together")
    func rendersWithUpdateBadgeAndSparkline() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateAvailableUpdate(AvailableUpdate(version: "2.0.0", downloadURL: URL(string: "https://example.com")!))

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let testPolls = [
            UsagePoll(id: 1, timestamp: now - 3600000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now, fiveHourUtil: 40.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(testPolls)

        let view = PopoverView(
            appState: appState,
            preferencesManager: MockPreferencesManager(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
        let controller = NSHostingController(rootView: view)
        _ = controller.view

        #expect(appState.availableUpdate != nil)
    }

    // MARK: - Task 5.5: onTap Callback Wiring (AC: 3)

    @Test("Sparkline onTap toggles AnalyticsWindow (AC 3)")
    func sparklineOnTapTogglesAnalyticsWindow() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )

        // Configure AnalyticsWindow with appState
        AnalyticsWindow.shared.configure(appState: appState, historicalDataService: MockHistoricalDataService())

        // Initial state: analytics window closed
        #expect(appState.isAnalyticsWindowOpen == false)

        // Simulate the onTap callback that PopoverView wires to Sparkline
        // This is the exact closure: { AnalyticsWindow.shared.toggle() }
        AnalyticsWindow.shared.toggle()

        // After toggle, analytics window should be open
        #expect(appState.isAnalyticsWindowOpen == true)

        // Clean up
        AnalyticsWindow.shared.close()
        #if DEBUG
        AnalyticsWindow.shared.reset()
        #endif
    }
}
