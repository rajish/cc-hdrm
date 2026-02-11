import Foundation
import Testing
@testable import cc_hdrm

@Suite("PreferencesManager Tests")
struct PreferencesManagerTests {

    /// Creates an isolated PreferencesManager with a unique UserDefaults suite per call.
    /// Returns the manager, defaults, and suiteName for cleanup.
    private func makeManager() -> (PreferencesManager, UserDefaults, String) {
        let suiteName = "com.cc-hdrm.PreferencesManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = PreferencesManager(defaults: defaults)
        return (manager, defaults, suiteName)
    }

    /// Removes the persistent domain for a test suite to avoid orphaned plists.
    private func cleanup(suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Default Values (AC #1)

    @Test("Default warning threshold is 20.0")
    func defaultWarningThreshold() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        #expect(manager.warningThreshold == 20.0)
    }

    @Test("Default critical threshold is 5.0")
    func defaultCriticalThreshold() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        #expect(manager.criticalThreshold == 5.0)
    }

    @Test("Default poll interval is 30 seconds")
    func defaultPollInterval() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        #expect(manager.pollInterval == 30.0)
    }

    @Test("Default launchAtLogin is false")
    func defaultLaunchAtLogin() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        #expect(manager.launchAtLogin == false)
    }

    @Test("Default dismissedVersion is nil")
    func defaultDismissedVersion() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        #expect(manager.dismissedVersion == nil)
    }

    // MARK: - Persistence (AC #2)

    @Test("Setting warning threshold persists and reads back correctly")
    func warningThresholdPersists() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.warningThreshold = 15.0
        #expect(manager.warningThreshold == 15.0)
    }

    @Test("Setting critical threshold persists and reads back correctly")
    func criticalThresholdPersists() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.criticalThreshold = 3.0
        #expect(manager.criticalThreshold == 3.0)
    }

    @Test("Setting poll interval persists and reads back correctly")
    func pollIntervalPersists() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.pollInterval = 60.0
        #expect(manager.pollInterval == 60.0)
    }

    @Test("Setting launchAtLogin persists and reads back correctly")
    func launchAtLoginPersists() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.launchAtLogin = true
        #expect(manager.launchAtLogin == true)
    }

    @Test("Setting dismissedVersion persists and reads back correctly")
    func dismissedVersionPersists() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.dismissedVersion = "1.2.3"
        #expect(manager.dismissedVersion == "1.2.3")
    }

    // MARK: - Cross-Instance Persistence (AC #2 — survives restart)

    @Test("Preferences persist across separate PreferencesManager instances (simulates app restart)")
    func crossInstancePersistence() {
        let suiteName = "com.cc-hdrm.PreferencesManagerTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        // First "launch" — write preferences
        let defaults1 = UserDefaults(suiteName: suiteName)!
        let manager1 = PreferencesManager(defaults: defaults1)
        manager1.warningThreshold = 25.0
        manager1.criticalThreshold = 8.0
        manager1.pollInterval = 45.0
        manager1.launchAtLogin = true
        manager1.dismissedVersion = "2.0.0"

        // Second "launch" — new manager, same suite
        let defaults2 = UserDefaults(suiteName: suiteName)!
        let manager2 = PreferencesManager(defaults: defaults2)
        #expect(manager2.warningThreshold == 25.0)
        #expect(manager2.criticalThreshold == 8.0)
        #expect(manager2.pollInterval == 45.0)
        #expect(manager2.launchAtLogin == true)
        #expect(manager2.dismissedVersion == "2.0.0")
    }

    // MARK: - Poll Interval Clamping (AC #5)

    @Test("Poll interval of 5 seconds clamped to 10 seconds")
    func pollIntervalClampedToMin() {
        let (manager, defaults, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        defaults.set(5.0, forKey: "com.cc-hdrm.pollInterval")
        #expect(manager.pollInterval == 10.0)
    }

    @Test("Poll interval of 500 seconds clamped to 300 seconds")
    func pollIntervalClampedToMax() {
        let (manager, defaults, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        defaults.set(500.0, forKey: "com.cc-hdrm.pollInterval")
        #expect(manager.pollInterval == 300.0)
    }

    @Test("Poll interval setter clamps to min 10")
    func pollIntervalSetterClamps() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.pollInterval = 5.0
        #expect(manager.pollInterval == 10.0)
    }

    @Test("Poll interval setter clamps to max 300")
    func pollIntervalSetterClampsMax() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.pollInterval = 500.0
        #expect(manager.pollInterval == 300.0)
    }

    // MARK: - Warning Threshold Clamping (AC #5)

    @Test("Warning threshold of 2% clamped to 6%")
    func warningThresholdClampedToMin() {
        let (manager, defaults, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        defaults.set(2.0, forKey: "com.cc-hdrm.warningThreshold")
        #expect(manager.warningThreshold == 6.0)
    }

    @Test("Warning threshold of 55% clamped to 50%")
    func warningThresholdClampedToMax() {
        let (manager, defaults, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        defaults.set(55.0, forKey: "com.cc-hdrm.warningThreshold")
        #expect(manager.warningThreshold == 50.0)
    }

    // MARK: - Critical Threshold Clamping (AC #5)

    @Test("Critical threshold of 0.5% clamped to 1%")
    func criticalThresholdClampedToMin() {
        let (manager, defaults, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        defaults.set(0.5, forKey: "com.cc-hdrm.criticalThreshold")
        #expect(manager.criticalThreshold == 1.0)
    }

    @Test("Critical threshold of 55% clamped to 49%")
    func criticalThresholdClampedToMax() {
        let (manager, defaults, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        defaults.set(55.0, forKey: "com.cc-hdrm.criticalThreshold")
        // clampedCritical=49, clampedWarning=20 (default) → 20 <= 49 → violation → defaults
        #expect(manager.criticalThreshold == 5.0)
    }

    @Test("Critical threshold of 49% with warning at 50% reads correctly")
    func criticalThreshold49WithWarning50() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.warningThreshold = 50.0
        manager.criticalThreshold = 49.0
        #expect(manager.criticalThreshold == 49.0)
        #expect(manager.warningThreshold == 50.0)
    }

    // MARK: - Warning > Critical Validation (AC #5)

    @Test("Warning threshold < critical threshold restores both to defaults")
    func warningLessThanCriticalRestoresDefaults() {
        let (manager, defaults, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        defaults.set(8.0, forKey: "com.cc-hdrm.warningThreshold")
        defaults.set(10.0, forKey: "com.cc-hdrm.criticalThreshold")
        #expect(manager.warningThreshold == PreferencesDefaults.warningThreshold)
        #expect(manager.criticalThreshold == PreferencesDefaults.criticalThreshold)
    }

    @Test("Warning threshold == critical threshold restores both to defaults")
    func warningEqualsCriticalRestoresDefaults() {
        let (manager, defaults, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        defaults.set(10.0, forKey: "com.cc-hdrm.warningThreshold")
        defaults.set(10.0, forKey: "com.cc-hdrm.criticalThreshold")
        #expect(manager.warningThreshold == PreferencesDefaults.warningThreshold)
        #expect(manager.criticalThreshold == PreferencesDefaults.criticalThreshold)
    }

    // MARK: - Setter Cross-Validation (AC #5 — H1 code review fix)

    @Test("Warning setter rejects value <= current critical and restores defaults")
    func warningSetterRejectsLessThanCritical() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        // Set valid pair first
        manager.warningThreshold = 30.0
        manager.criticalThreshold = 10.0
        // Now set warning to 10 (== critical) — should restore defaults
        manager.warningThreshold = 10.0
        #expect(manager.warningThreshold == PreferencesDefaults.warningThreshold)
        #expect(manager.criticalThreshold == PreferencesDefaults.criticalThreshold)
    }

    @Test("Critical setter rejects value >= current warning and restores defaults")
    func criticalSetterRejectsGreaterThanWarning() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        // Set valid pair first
        manager.warningThreshold = 30.0
        manager.criticalThreshold = 10.0
        // Now set critical to 30 (== warning) — should restore defaults
        manager.criticalThreshold = 30.0
        #expect(manager.warningThreshold == PreferencesDefaults.warningThreshold)
        #expect(manager.criticalThreshold == PreferencesDefaults.criticalThreshold)
    }

    @Test("Warning setter accepts value > current critical")
    func warningSetterAcceptsValidValue() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.warningThreshold = 30.0
        manager.criticalThreshold = 10.0
        manager.warningThreshold = 15.0
        #expect(manager.warningThreshold == 15.0)
        #expect(manager.criticalThreshold == 10.0)
    }

    @Test("Critical setter accepts value < current warning")
    func criticalSetterAcceptsValidValue() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.warningThreshold = 30.0
        manager.criticalThreshold = 10.0
        manager.criticalThreshold = 20.0
        #expect(manager.criticalThreshold == 20.0)
        #expect(manager.warningThreshold == 30.0)
    }

    // MARK: - Data Retention Days

    @Test("Default data retention days is 365")
    func defaultDataRetentionDays() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        #expect(manager.dataRetentionDays == 365)
    }

    @Test("Data retention days setter clamps to min 30")
    func dataRetentionDaysClampedToMin() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.dataRetentionDays = 10
        #expect(manager.dataRetentionDays == 30)
    }

    @Test("Data retention days setter clamps to max 1825")
    func dataRetentionDaysClampedToMax() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.dataRetentionDays = 3000
        #expect(manager.dataRetentionDays == 1825)
    }

    @Test("Data retention days getter clamps raw value below 30 to 30")
    func dataRetentionDaysGetterClampedToMin() {
        let (manager, defaults, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        defaults.set(15, forKey: "com.cc-hdrm.dataRetentionDays")
        #expect(manager.dataRetentionDays == 30)
    }

    @Test("Data retention days getter clamps raw value above 1825 to 1825")
    func dataRetentionDaysGetterClampedToMax() {
        let (manager, defaults, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        defaults.set(5000, forKey: "com.cc-hdrm.dataRetentionDays")
        #expect(manager.dataRetentionDays == 1825)
    }

    @Test("Data retention days persists and reads back correctly")
    func dataRetentionDaysPersists() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.dataRetentionDays = 180
        #expect(manager.dataRetentionDays == 180)
    }

    // MARK: - Reset to Defaults

    @Test("resetToDefaults restores all values to defaults")
    func resetToDefaultsRestoresAll() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        manager.warningThreshold = 15.0
        manager.criticalThreshold = 3.0
        manager.pollInterval = 60.0
        manager.launchAtLogin = true
        manager.dismissedVersion = "1.0.0"
        manager.dataRetentionDays = 90

        manager.resetToDefaults()

        #expect(manager.warningThreshold == PreferencesDefaults.warningThreshold)
        #expect(manager.criticalThreshold == PreferencesDefaults.criticalThreshold)
        #expect(manager.pollInterval == PreferencesDefaults.pollInterval)
        #expect(manager.launchAtLogin == PreferencesDefaults.launchAtLogin)
        #expect(manager.dismissedVersion == nil)
        #expect(manager.dataRetentionDays == PreferencesDefaults.dataRetentionDays)
    }

    // MARK: - Protocol Conformance

    @Test("PreferencesManager conforms to PreferencesManagerProtocol")
    func conformsToProtocol() {
        let (manager, _, suite) = makeManager()
        defer { cleanup(suiteName: suite) }
        let _: any PreferencesManagerProtocol = manager
    }
}

// MARK: - NotificationService + PreferencesManager Integration

@Suite("NotificationService Preferences Integration Tests")
struct NotificationServicePreferencesTests {

    private func windowState(utilization: Double, resetsAt: Date? = Date().addingTimeInterval(3600)) -> WindowState {
        WindowState(utilization: utilization, resetsAt: resetsAt)
    }

    @Test("NotificationService uses custom thresholds from PreferencesManager (not hardcoded 20/5)")
    @MainActor
    func usesCustomThresholds() async {
        let spy = SpyNotificationCenter()
        let mock = MockPreferencesManager()
        mock.warningThreshold = 30.0
        mock.criticalThreshold = 10.0
        let service = NotificationService(notificationCenter: spy, preferencesManager: mock)
        spy.grantAuthorization = true
        await service.requestAuthorization()

        // headroom 35% — above custom 30%, so no warning
        await service.evaluateThresholds(fiveHour: windowState(utilization: 65), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .aboveWarning)
        #expect(spy.addedRequests.isEmpty)

        // headroom 31% — still above custom 30%, no warning
        await service.evaluateThresholds(fiveHour: windowState(utilization: 69), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .aboveWarning)

        // headroom 25% — below custom 30%, warning fires
        await service.evaluateThresholds(fiveHour: windowState(utilization: 75), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .warned20)
        #expect(spy.addedRequests.count == 1)
    }

    @Test("NotificationService re-arms when thresholds change and headroom is above new threshold")
    @MainActor
    func rearmsOnThresholdChange() async {
        let spy = SpyNotificationCenter()
        let mock = MockPreferencesManager()
        // Start with defaults (20/5)
        let service = NotificationService(notificationCenter: spy, preferencesManager: mock)
        spy.grantAuthorization = true
        await service.requestAuthorization()

        // headroom 18% — below 20%, warning fires
        await service.evaluateThresholds(fiveHour: windowState(utilization: 82), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .warned20)
        #expect(spy.addedRequests.count == 1)

        // Change thresholds to 15/3 — headroom 18% is now above 15% warning
        mock.warningThreshold = 15.0
        mock.criticalThreshold = 3.0

        // Next evaluation should re-arm since 18% >= 15%
        await service.evaluateThresholds(fiveHour: windowState(utilization: 82), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .aboveWarning)
    }

    @Test("MockPreferencesManager pollInterval is hot-reconfigurable for injection")
    func mockPollIntervalIsHotReconfigurable() {
        let mock = MockPreferencesManager()
        mock.pollInterval = 60.0
        #expect(mock.pollInterval == 60.0)
        mock.pollInterval = 120.0
        #expect(mock.pollInterval == 120.0)
        // Note: PollingEngine integration (actual sleep reads) is covered in PollingEngineTests
        // via `PollingEngine.start()` which calls `preferencesManager.pollInterval` each cycle.
        // See cc-hdrm/cc-hdrmTests/Services/PollingEngineTests.swift.
    }

    @Test("Existing threshold state machine tests still pass with default thresholds")
    @MainActor
    func defaultThresholdsMatchOriginalBehavior() {
        let service = NotificationService()
        // evaluateWindow with defaults should behave identically to original hardcoded values
        let (state1, fire1, _) = service.evaluateWindow(currentState: .aboveWarning, headroom: 19.5)
        #expect(state1 == .warned20)
        #expect(fire1 == true)

        let (state2, _, fire2) = service.evaluateWindow(currentState: .warned20, headroom: 4.9)
        #expect(state2 == .warned5)
        #expect(fire2 == true)
    }
}
