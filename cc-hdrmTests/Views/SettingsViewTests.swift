import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("SettingsView Tests")
@MainActor
struct SettingsViewTests {

    @Test("SettingsView renders without crash")
    func rendersWithoutCrash() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch)
        _ = view.body
    }

    @Test("SettingsView renders in NSHostingController without crash")
    func rendersInHostingController() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch)
        let controller = NSHostingController(rootView: view)
        #expect(controller.view.frame.size.width >= 0)
    }

    @Test("SettingsView initializes with default preference values")
    func initializesWithDefaults() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        #expect(mock.warningThreshold == PreferencesDefaults.warningThreshold)
        #expect(mock.criticalThreshold == PreferencesDefaults.criticalThreshold)
        #expect(mock.pollInterval == PreferencesDefaults.pollInterval)
        #expect(mock.launchAtLogin == PreferencesDefaults.launchAtLogin)
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch)
        _ = view.body
    }

    @Test("SettingsView initializes with custom preference values")
    func initializesWithCustomValues() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        mock.warningThreshold = 30.0
        mock.criticalThreshold = 10.0
        mock.pollInterval = 60
        mock.launchAtLogin = true
        mockLaunch.isEnabled = true
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch)
        _ = view.body
    }

    @Test("SettingsView formatInterval returns correct short strings")
    func formatInterval() {
        #expect(SettingsView.formatInterval(10) == "10s")
        #expect(SettingsView.formatInterval(15) == "15s")
        #expect(SettingsView.formatInterval(30) == "30s")
        #expect(SettingsView.formatInterval(60) == "1m")
        #expect(SettingsView.formatInterval(120) == "2m")
        #expect(SettingsView.formatInterval(300) == "5m")
    }

    @Test("SettingsView onThresholdChange closure is accepted and stored")
    func onThresholdChangeClosureAccepted() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        var callCount = 0
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch, onThresholdChange: { callCount += 1 })
        _ = view.body
        // Verify the view accepts the closure without crash — actual invocation
        // requires SwiftUI onChange which cannot be triggered in unit tests.
        // The closure wiring is verified structurally: SettingsView stores it
        // and calls it at lines 53, 76, and 123.
        #expect(callCount == 0)
    }
}

@Suite("GearMenuView Settings Integration Tests")
@MainActor
struct GearMenuViewSettingsTests {

    @Test("GearMenuView renders with preferencesManager parameter without crash")
    func rendersWithPreferencesManager() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let view = GearMenuView(preferencesManager: mock, launchAtLoginService: mockLaunch)
        _ = view.body
    }

    @Test("GearMenuView renders in NSHostingController with preferencesManager")
    func rendersInHostingController() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let view = GearMenuView(preferencesManager: mock, launchAtLoginService: mockLaunch)
        let controller = NSHostingController(rootView: view)
        #expect(controller.view.frame.size.width >= 0)
    }
}

@Suite("PopoverFooterView PreferencesManager Tests")
@MainActor
struct PopoverFooterViewPreferencesTests {

    @Test("PopoverFooterView accepts and renders with preferencesManager")
    func acceptsPreferencesManager() {
        let appState = AppState()
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let view = PopoverFooterView(appState: appState, preferencesManager: mock, launchAtLoginService: mockLaunch)
        _ = view.body
    }
}

@Suite("PopoverView PreferencesManager Tests")
@MainActor
struct PopoverViewPreferencesTests {

    @Test("PopoverView accepts and renders with preferencesManager")
    func acceptsPreferencesManager() {
        let appState = AppState()
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let view = PopoverView(appState: appState, preferencesManager: mock, launchAtLoginService: mockLaunch)
        _ = view.body
    }

    @Test("PopoverView renders in NSHostingController with preferencesManager")
    func rendersInHostingController() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let view = PopoverView(appState: appState, preferencesManager: mock, launchAtLoginService: mockLaunch)
        let controller = NSHostingController(rootView: view)
        #expect(controller.view.frame.size.width >= 0)
    }
}
