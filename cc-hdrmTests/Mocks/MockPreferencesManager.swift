import Foundation
@testable import cc_hdrm

/// In-memory mock for PreferencesManagerProtocol. No UserDefaults involved.
final class MockPreferencesManager: PreferencesManagerProtocol {
    var warningThreshold: Double = PreferencesDefaults.warningThreshold
    var criticalThreshold: Double = PreferencesDefaults.criticalThreshold
    var pollInterval: TimeInterval = PreferencesDefaults.pollInterval
    var launchAtLogin: Bool = PreferencesDefaults.launchAtLogin
    var dismissedVersion: String?
    var dataRetentionDays: Int = PreferencesDefaults.dataRetentionDays
    var customFiveHourCredits: Int?
    var customSevenDayCredits: Int?
    var customMonthlyPrice: Double?
    var billingCycleDay: Int?
    var patternNotificationCooldowns: [String: Date] = [:]
    var dismissedPatternFindings: Set<String> = []
    var dismissedTierRecommendation: String?
    var extraUsageAlertsEnabled: Bool = PreferencesDefaults.extraUsageAlertsEnabled
    var extraUsageThreshold50Enabled: Bool = PreferencesDefaults.extraUsageThreshold50Enabled
    var extraUsageThreshold75Enabled: Bool = PreferencesDefaults.extraUsageThreshold75Enabled
    var extraUsageThreshold90Enabled: Bool = PreferencesDefaults.extraUsageThreshold90Enabled
    var extraUsageEnteredAlertEnabled: Bool = PreferencesDefaults.extraUsageEnteredAlertEnabled
    var extraUsageFiredThresholds: Set<Int> = []
    var extraUsageEnteredAlertFired: Bool = false
    var extraUsageLastBillingPeriodKey: String?
    var resetToDefaultsCallCount = 0

    func resetToDefaults() {
        resetToDefaultsCallCount += 1
        warningThreshold = PreferencesDefaults.warningThreshold
        criticalThreshold = PreferencesDefaults.criticalThreshold
        pollInterval = PreferencesDefaults.pollInterval
        launchAtLogin = PreferencesDefaults.launchAtLogin
        dismissedVersion = nil
        dataRetentionDays = PreferencesDefaults.dataRetentionDays
        customFiveHourCredits = nil
        customSevenDayCredits = nil
        customMonthlyPrice = nil
        billingCycleDay = nil
        patternNotificationCooldowns = [:]
        dismissedPatternFindings = []
        dismissedTierRecommendation = nil
        extraUsageAlertsEnabled = PreferencesDefaults.extraUsageAlertsEnabled
        extraUsageThreshold50Enabled = PreferencesDefaults.extraUsageThreshold50Enabled
        extraUsageThreshold75Enabled = PreferencesDefaults.extraUsageThreshold75Enabled
        extraUsageThreshold90Enabled = PreferencesDefaults.extraUsageThreshold90Enabled
        extraUsageEnteredAlertEnabled = PreferencesDefaults.extraUsageEnteredAlertEnabled
        extraUsageFiredThresholds = []
        extraUsageEnteredAlertFired = false
        extraUsageLastBillingPeriodKey = nil
    }
}
