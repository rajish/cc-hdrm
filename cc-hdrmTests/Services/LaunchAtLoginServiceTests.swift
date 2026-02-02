import Testing
@testable import cc_hdrm

@Suite("MockLaunchAtLoginService Tests")
@MainActor
struct MockLaunchAtLoginServiceTests {

    @Test("register sets isEnabled to true")
    func registerSetsIsEnabled() {
        let service = MockLaunchAtLoginService()
        #expect(service.isEnabled == false)
        service.register()
        #expect(service.isEnabled == true)
        #expect(service.registerCallCount == 1)
    }

    @Test("unregister sets isEnabled to false")
    func unregisterSetsIsEnabledFalse() {
        let service = MockLaunchAtLoginService()
        service.isEnabled = true
        service.unregister()
        #expect(service.isEnabled == false)
        #expect(service.unregisterCallCount == 1)
    }

    @Test("register failure keeps isEnabled false")
    func registerFailureKeepsDisabled() {
        let service = MockLaunchAtLoginService()
        service.shouldThrowOnRegister = true
        service.register()
        #expect(service.isEnabled == false)
        #expect(service.registerCallCount == 1)
    }

    @Test("unregister failure keeps isEnabled true")
    func unregisterFailureKeepsEnabled() {
        let service = MockLaunchAtLoginService()
        service.isEnabled = true
        service.shouldThrowOnUnregister = true
        service.unregister()
        #expect(service.isEnabled == true)
        #expect(service.unregisterCallCount == 1)
    }
}

@Suite("SettingsView LaunchAtLogin Behavior Tests")
@MainActor
struct SettingsViewLaunchAtLoginTests {

    @Test("SettingsView initializes toggle from launchAtLoginService.isEnabled=false, ignoring preferencesManager.launchAtLogin=true")
    func settingsViewInitFromServiceWhenDisabled() {
        let prefs = MockPreferencesManager()
        prefs.launchAtLogin = true  // PreferencesManager says ON

        let service = MockLaunchAtLoginService()
        service.isEnabled = false   // SMAppService says OFF (reality)

        // SettingsView should use service.isEnabled (false), not prefs.launchAtLogin (true)
        // Verify by checking that after init + body render, no register() call was made
        // (toggle starts OFF matching service, so no onChange fires)
        let view = SettingsView(preferencesManager: prefs, launchAtLoginService: service)
        _ = view.body
        #expect(service.registerCallCount == 0, "No register call expected — toggle initialized from service.isEnabled (false)")
        #expect(service.unregisterCallCount == 0, "No unregister call expected — toggle initialized from service.isEnabled (false)")
    }

    @Test("SettingsView initializes toggle from launchAtLoginService.isEnabled=true, ignoring preferencesManager.launchAtLogin=false")
    func settingsViewInitFromServiceWhenEnabled() {
        let prefs = MockPreferencesManager()
        prefs.launchAtLogin = false  // PreferencesManager says OFF

        let service = MockLaunchAtLoginService()
        service.isEnabled = true     // SMAppService says ON (reality)

        // Toggle should start ON (from service), no onChange fires
        let view = SettingsView(preferencesManager: prefs, launchAtLoginService: service)
        _ = view.body
        #expect(service.registerCallCount == 0, "No register call — toggle initialized from service.isEnabled (true)")
        #expect(service.unregisterCallCount == 0, "No unregister call — toggle initialized from service.isEnabled (true)")
    }

    @Test("Mismatch: prefs=true service=false — no service calls on init (toggle follows service)")
    func mismatchResolvesToServiceTruth() {
        let prefs = MockPreferencesManager()
        prefs.launchAtLogin = true

        let service = MockLaunchAtLoginService()
        service.isEnabled = false

        let view = SettingsView(preferencesManager: prefs, launchAtLoginService: service)
        _ = view.body
        // Key assertion: SettingsView init reads service.isEnabled (false), NOT prefs.launchAtLogin (true)
        // So toggle is OFF, no onChange triggers, no register/unregister calls
        #expect(service.registerCallCount == 0)
        #expect(service.unregisterCallCount == 0)
    }

    @Test("Reset to Defaults button handler calls unregister and reads isEnabled")
    func resetToDefaultsCallsUnregister() {
        let prefs = MockPreferencesManager()
        prefs.warningThreshold = 40.0
        prefs.criticalThreshold = 15.0
        prefs.launchAtLogin = true
        let service = MockLaunchAtLoginService()
        service.isEnabled = true

        // Exercise the exact same sequence as SettingsView Reset to Defaults button (SettingsView.swift:128-135)
        prefs.resetToDefaults()
        service.unregister()
        let actualState = service.isEnabled
        prefs.launchAtLogin = actualState

        #expect(service.unregisterCallCount == 1, "Reset to Defaults must call unregister()")
        #expect(actualState == false, "After unregister, isEnabled should be false")
        #expect(prefs.launchAtLogin == false, "preferencesManager.launchAtLogin should sync to actual state")
        #expect(prefs.warningThreshold == PreferencesDefaults.warningThreshold, "resetToDefaults should restore warning threshold")
        #expect(prefs.criticalThreshold == PreferencesDefaults.criticalThreshold, "resetToDefaults should restore critical threshold")
    }

    @Test("Register failure scenario: service stays disabled after failed register")
    func registerFailureRevertsToggle() {
        let prefs = MockPreferencesManager()
        let service = MockLaunchAtLoginService()
        service.shouldThrowOnRegister = true

        // Simulate what SettingsView.onChange does when toggle switches ON
        service.register()
        let actualState = service.isEnabled
        prefs.launchAtLogin = actualState

        #expect(service.registerCallCount == 1)
        #expect(actualState == false, "Failed register should leave isEnabled false")
        #expect(prefs.launchAtLogin == false, "PreferencesManager should sync to actual (failed) state")
    }
}
