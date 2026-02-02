import Foundation
@testable import cc_hdrm

/// In-memory mock for PreferencesManagerProtocol. No UserDefaults involved.
final class MockPreferencesManager: PreferencesManagerProtocol {
    var warningThreshold: Double = PreferencesDefaults.warningThreshold
    var criticalThreshold: Double = PreferencesDefaults.criticalThreshold
    var pollInterval: TimeInterval = PreferencesDefaults.pollInterval
    var launchAtLogin: Bool = PreferencesDefaults.launchAtLogin
    var dismissedVersion: String?
    var resetToDefaultsCallCount = 0

    func resetToDefaults() {
        resetToDefaultsCallCount += 1
        warningThreshold = PreferencesDefaults.warningThreshold
        criticalThreshold = PreferencesDefaults.criticalThreshold
        pollInterval = PreferencesDefaults.pollInterval
        launchAtLogin = PreferencesDefaults.launchAtLogin
        dismissedVersion = nil
    }
}
