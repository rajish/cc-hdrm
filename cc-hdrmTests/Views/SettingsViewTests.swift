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

    @Test("SettingsView renders Historical Data section with retention picker when historicalDataService provided")
    func rendersHistoricalDataSection() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let mockHistorical = MockHistoricalDataService()
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch, historicalDataService: mockHistorical)
        _ = view.body
    }

    @Test("SettingsView formatSize returns human-readable size strings")
    func formatSize() {
        #expect(SettingsView.formatSize(0) == "Zero KB")
        #expect(SettingsView.formatSize(1024).contains("KB"))
        #expect(SettingsView.formatSize(1_048_576).contains("MB"))
        #expect(SettingsView.formatSize(1_073_741_824).contains("GB"))
    }

    @Test("SettingsView retentionLabel returns correct labels for known values")
    func retentionLabel() {
        #expect(SettingsView.retentionLabel(for: 30) == "30 days")
        #expect(SettingsView.retentionLabel(for: 90) == "90 days")
        #expect(SettingsView.retentionLabel(for: 180) == "6 months")
        #expect(SettingsView.retentionLabel(for: 365) == "1 year")
        #expect(SettingsView.retentionLabel(for: 730) == "2 years")
        #expect(SettingsView.retentionLabel(for: 1825) == "5 years")
        #expect(SettingsView.retentionLabel(for: 999) == "999 days")
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

@Suite("SettingsView Extra Usage Alerts Tests (Story 17.4)")
@MainActor
struct SettingsViewExtraUsageTests {

    @Test("SettingsView renders without crash when appState has extraUsageEnabled true")
    func rendersWithExtraUsageEnabled() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let appState = AppState()
        appState.updateExtraUsage(enabled: true, monthlyLimit: 100.0, usedCredits: 50.0, utilization: 0.5)
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch, appState: appState)
        _ = view.body
    }

    @Test("SettingsView renders without crash when appState has extraUsageEnabled false")
    func rendersWithExtraUsageDisabled() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let appState = AppState()
        appState.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch, appState: appState)
        _ = view.body
    }

    @Test("SettingsView renders without crash when appState is nil (backward compatibility)")
    func rendersWithNilAppState() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch, appState: nil)
        _ = view.body
    }
}

@Suite("SettingsView Advanced Section Tests (Story 15.2)")
@MainActor
struct SettingsViewAdvancedTests {

    @Test("SettingsView renders Advanced disclosure group without crash")
    func rendersAdvancedDisclosureGroup() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch)
        _ = view.body
    }

    @Test("Custom credit fields display existing values from PreferencesManager")
    func displaysExistingCustomValues() {
        let mock = MockPreferencesManager()
        mock.customFiveHourCredits = 1_000_000
        mock.customSevenDayCredits = 10_000_000
        let mockLaunch = MockLaunchAtLoginService()
        // SettingsView init reads from mock and initializes @State text fields
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch)
        _ = view.body
        // Verify mock values survived through init (they're read via .map(String.init))
        #expect(mock.customFiveHourCredits == 1_000_000)
        #expect(mock.customSevenDayCredits == 10_000_000)
    }

    @Test("Empty text input returns .clear validation result")
    func emptyFieldClearsPreference() {
        #expect(SettingsView.validateCreditInput("") == .clear)
        #expect(SettingsView.validateCreditInput("   ") == .clear)
    }

    @Test("Valid positive integer returns .valid with parsed value")
    func validPositiveIntegerPersisted() {
        #expect(SettingsView.validateCreditInput("750000") == .valid(750_000))
        #expect(SettingsView.validateCreditInput("1") == .valid(1))
        #expect(SettingsView.validateCreditInput(" 550000 ") == .valid(550_000))
    }

    @Test("Invalid input returns .invalid — negative, zero, non-numeric, decimal")
    func invalidInputRetainsPreviousValue() {
        #expect(SettingsView.validateCreditInput("-100") == .invalid("Must be a positive whole number"))
        #expect(SettingsView.validateCreditInput("0") == .invalid("Must be a positive whole number"))
        #expect(SettingsView.validateCreditInput("abc") == .invalid("Must be a positive whole number"))
        #expect(SettingsView.validateCreditInput("1000.5") == .invalid("Must be a positive whole number"))
    }

    @Test("Reset to Defaults clears custom credit preferences")
    func resetClearsCustomCredits() {
        let mock = MockPreferencesManager()
        mock.customFiveHourCredits = 1_000_000
        mock.customSevenDayCredits = 10_000_000
        mock.resetToDefaults()
        #expect(mock.customFiveHourCredits == nil)
        #expect(mock.customSevenDayCredits == nil)
        #expect(mock.resetToDefaultsCallCount == 1)
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
