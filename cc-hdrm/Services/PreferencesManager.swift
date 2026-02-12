import Foundation
import os

/// Manages user preferences with UserDefaults persistence and validation clamping.
/// This is the ONLY component that reads/writes UserDefaults for preferences.
final class PreferencesManager: PreferencesManagerProtocol {
    private let defaults: UserDefaults

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "preferences"
    )

    private enum Keys {
        static let warningThreshold = "com.cc-hdrm.warningThreshold"
        static let criticalThreshold = "com.cc-hdrm.criticalThreshold"
        static let pollInterval = "com.cc-hdrm.pollInterval"
        static let launchAtLogin = "com.cc-hdrm.launchAtLogin"
        static let dismissedVersion = "com.cc-hdrm.dismissedVersion"
        static let dataRetentionDays = "com.cc-hdrm.dataRetentionDays"
        static let customFiveHourCredits = "com.cc-hdrm.customFiveHourCredits"
        static let customSevenDayCredits = "com.cc-hdrm.customSevenDayCredits"
        static let customMonthlyPrice = "com.cc-hdrm.customMonthlyPrice"
        static let billingCycleDay = "com.cc-hdrm.billingCycleDay"
        static let patternNotificationCooldowns = "com.cc-hdrm.patternNotificationCooldowns"
        static let dismissedPatternFindings = "com.cc-hdrm.dismissedPatternFindings"
        static let dismissedTierRecommendation = "com.cc-hdrm.dismissedTierRecommendation"
        static let extraUsageAlertsEnabled = "com.cc-hdrm.extraUsageAlertsEnabled"
        static let extraUsageThreshold50Enabled = "com.cc-hdrm.extraUsageThreshold50Enabled"
        static let extraUsageThreshold75Enabled = "com.cc-hdrm.extraUsageThreshold75Enabled"
        static let extraUsageThreshold90Enabled = "com.cc-hdrm.extraUsageThreshold90Enabled"
        static let extraUsageEnteredAlertEnabled = "com.cc-hdrm.extraUsageEnteredAlertEnabled"
        static let extraUsageFiredThresholds = "com.cc-hdrm.extraUsageFiredThresholds"
        static let extraUsageEnteredAlertFired = "com.cc-hdrm.extraUsageEnteredAlertFired"
        static let extraUsageLastBillingPeriodKey = "com.cc-hdrm.extraUsageLastBillingPeriodKey"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Warning Threshold

    var warningThreshold: Double {
        get {
            let warning = defaults.double(forKey: Keys.warningThreshold)
            let critical = defaults.double(forKey: Keys.criticalThreshold)
            guard warning > 0 else { return PreferencesDefaults.warningThreshold }
            let clampedWarning = min(max(warning, 6), 50)
            let clampedCritical = min(max(critical > 0 ? critical : PreferencesDefaults.criticalThreshold, 1), 49)
            if clampedWarning <= clampedCritical {
                Self.logger.warning("Warning threshold (\(clampedWarning)) <= critical threshold (\(clampedCritical)) — restoring defaults")
                defaults.removeObject(forKey: Keys.warningThreshold)
                defaults.removeObject(forKey: Keys.criticalThreshold)
                return PreferencesDefaults.warningThreshold
            }
            return clampedWarning
        }
        set {
            let clamped = min(max(newValue, 6), 50)
            let currentCritical = defaults.double(forKey: Keys.criticalThreshold)
            let effectiveCritical = currentCritical > 0
                ? min(max(currentCritical, 1), 49)
                : PreferencesDefaults.criticalThreshold
            if clamped <= effectiveCritical {
                Self.logger.warning("Warning threshold \(clamped)% <= critical \(effectiveCritical)% — restoring defaults")
                defaults.removeObject(forKey: Keys.warningThreshold)
                defaults.removeObject(forKey: Keys.criticalThreshold)
                return
            }
            Self.logger.info("Warning threshold changed to \(clamped)%")
            defaults.set(clamped, forKey: Keys.warningThreshold)
        }
    }

    // MARK: - Critical Threshold

    var criticalThreshold: Double {
        get {
            let warning = defaults.double(forKey: Keys.warningThreshold)
            let critical = defaults.double(forKey: Keys.criticalThreshold)
            guard critical > 0 else { return PreferencesDefaults.criticalThreshold }
            let clampedCritical = min(max(critical, 1), 49)
            let clampedWarning = min(max(warning > 0 ? warning : PreferencesDefaults.warningThreshold, 6), 50)
            if clampedWarning <= clampedCritical {
                Self.logger.warning("Warning threshold (\(clampedWarning)) <= critical threshold (\(clampedCritical)) — restoring defaults")
                defaults.removeObject(forKey: Keys.warningThreshold)
                defaults.removeObject(forKey: Keys.criticalThreshold)
                return PreferencesDefaults.criticalThreshold
            }
            return clampedCritical
        }
        set {
            let clamped = min(max(newValue, 1), 49)
            let currentWarning = defaults.double(forKey: Keys.warningThreshold)
            let effectiveWarning = currentWarning > 0
                ? min(max(currentWarning, 6), 50)
                : PreferencesDefaults.warningThreshold
            if effectiveWarning <= clamped {
                Self.logger.warning("Critical threshold \(clamped)% >= warning \(effectiveWarning)% — restoring defaults")
                defaults.removeObject(forKey: Keys.warningThreshold)
                defaults.removeObject(forKey: Keys.criticalThreshold)
                return
            }
            Self.logger.info("Critical threshold changed to \(clamped)%")
            defaults.set(clamped, forKey: Keys.criticalThreshold)
        }
    }

    // MARK: - Poll Interval

    var pollInterval: TimeInterval {
        get {
            let raw = defaults.double(forKey: Keys.pollInterval)
            guard raw > 0 else { return PreferencesDefaults.pollInterval }
            return min(max(raw, 10), 300)
        }
        set {
            let clamped = min(max(newValue, 10), 300)
            Self.logger.info("Poll interval changed to \(clamped)s")
            defaults.set(clamped, forKey: Keys.pollInterval)
        }
    }

    // MARK: - Launch at Login

    var launchAtLogin: Bool {
        get {
            // UserDefaults.bool returns false if key doesn't exist, which matches default
            defaults.bool(forKey: Keys.launchAtLogin)
        }
        set {
            Self.logger.info("Launch at login changed to \(newValue)")
            defaults.set(newValue, forKey: Keys.launchAtLogin)
        }
    }

    // MARK: - Dismissed Version

    var dismissedVersion: String? {
        get {
            defaults.string(forKey: Keys.dismissedVersion)
        }
        set {
            Self.logger.info("Dismissed version changed to \(newValue ?? "nil", privacy: .public)")
            defaults.set(newValue, forKey: Keys.dismissedVersion)
        }
    }

    // MARK: - Data Retention

    var dataRetentionDays: Int {
        get {
            let raw = defaults.integer(forKey: Keys.dataRetentionDays)
            guard raw > 0 else { return PreferencesDefaults.dataRetentionDays }
            return min(max(raw, 30), 1825)
        }
        set {
            let clamped = min(max(newValue, 30), 1825)
            Self.logger.info("Data retention changed to \(clamped) days")
            defaults.set(clamped, forKey: Keys.dataRetentionDays)
        }
    }

    // MARK: - Custom Credit Limits

    var customFiveHourCredits: Int? {
        get {
            let value = defaults.integer(forKey: Keys.customFiveHourCredits)
            return value > 0 ? value : nil
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.customFiveHourCredits)
            } else {
                defaults.removeObject(forKey: Keys.customFiveHourCredits)
            }
        }
    }

    var customSevenDayCredits: Int? {
        get {
            let value = defaults.integer(forKey: Keys.customSevenDayCredits)
            return value > 0 ? value : nil
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.customSevenDayCredits)
            } else {
                defaults.removeObject(forKey: Keys.customSevenDayCredits)
            }
        }
    }

    var customMonthlyPrice: Double? {
        get {
            let value = defaults.double(forKey: Keys.customMonthlyPrice)
            return value > 0 ? value : nil
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.customMonthlyPrice)
            } else {
                defaults.removeObject(forKey: Keys.customMonthlyPrice)
            }
        }
    }

    // MARK: - Billing Cycle Day

    var billingCycleDay: Int? {
        get {
            let value = defaults.integer(forKey: Keys.billingCycleDay)
            return (value >= 1 && value <= 28) ? value : nil
        }
        set {
            if let newValue {
                let clamped = min(max(newValue, 1), 28)
                Self.logger.info("Billing cycle day changed to \(clamped)")
                defaults.set(clamped, forKey: Keys.billingCycleDay)
            } else {
                defaults.removeObject(forKey: Keys.billingCycleDay)
            }
        }
    }

    // MARK: - Pattern Notification Cooldowns

    var patternNotificationCooldowns: [String: Date] {
        get {
            guard let data = defaults.data(forKey: Keys.patternNotificationCooldowns) else { return [:] }
            return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.patternNotificationCooldowns)
            }
        }
    }

    // MARK: - Dismissed Pattern Findings

    var dismissedPatternFindings: Set<String> {
        get {
            let array = defaults.stringArray(forKey: Keys.dismissedPatternFindings) ?? []
            return Set(array)
        }
        set {
            defaults.set(Array(newValue), forKey: Keys.dismissedPatternFindings)
        }
    }

    // MARK: - Dismissed Tier Recommendation

    var dismissedTierRecommendation: String? {
        get {
            defaults.string(forKey: Keys.dismissedTierRecommendation)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.dismissedTierRecommendation)
            } else {
                defaults.removeObject(forKey: Keys.dismissedTierRecommendation)
            }
        }
    }

    // MARK: - Extra Usage Alert Preferences

    var extraUsageAlertsEnabled: Bool {
        get { defaults.object(forKey: Keys.extraUsageAlertsEnabled) == nil ? PreferencesDefaults.extraUsageAlertsEnabled : defaults.bool(forKey: Keys.extraUsageAlertsEnabled) }
        set {
            Self.logger.info("Extra usage alerts enabled changed to \(newValue)")
            defaults.set(newValue, forKey: Keys.extraUsageAlertsEnabled)
        }
    }

    var extraUsageThreshold50Enabled: Bool {
        get { defaults.object(forKey: Keys.extraUsageThreshold50Enabled) == nil ? PreferencesDefaults.extraUsageThreshold50Enabled : defaults.bool(forKey: Keys.extraUsageThreshold50Enabled) }
        set { defaults.set(newValue, forKey: Keys.extraUsageThreshold50Enabled) }
    }

    var extraUsageThreshold75Enabled: Bool {
        get { defaults.object(forKey: Keys.extraUsageThreshold75Enabled) == nil ? PreferencesDefaults.extraUsageThreshold75Enabled : defaults.bool(forKey: Keys.extraUsageThreshold75Enabled) }
        set { defaults.set(newValue, forKey: Keys.extraUsageThreshold75Enabled) }
    }

    var extraUsageThreshold90Enabled: Bool {
        get { defaults.object(forKey: Keys.extraUsageThreshold90Enabled) == nil ? PreferencesDefaults.extraUsageThreshold90Enabled : defaults.bool(forKey: Keys.extraUsageThreshold90Enabled) }
        set { defaults.set(newValue, forKey: Keys.extraUsageThreshold90Enabled) }
    }

    var extraUsageEnteredAlertEnabled: Bool {
        get { defaults.object(forKey: Keys.extraUsageEnteredAlertEnabled) == nil ? PreferencesDefaults.extraUsageEnteredAlertEnabled : defaults.bool(forKey: Keys.extraUsageEnteredAlertEnabled) }
        set { defaults.set(newValue, forKey: Keys.extraUsageEnteredAlertEnabled) }
    }

    // MARK: - Extra Usage Threshold Tracking

    var extraUsageFiredThresholds: Set<Int> {
        get {
            guard let data = defaults.data(forKey: Keys.extraUsageFiredThresholds) else { return [] }
            return (try? JSONDecoder().decode(Set<Int>.self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.extraUsageFiredThresholds)
            }
        }
    }

    var extraUsageEnteredAlertFired: Bool {
        get { defaults.bool(forKey: Keys.extraUsageEnteredAlertFired) }
        set { defaults.set(newValue, forKey: Keys.extraUsageEnteredAlertFired) }
    }

    var extraUsageLastBillingPeriodKey: String? {
        get { defaults.string(forKey: Keys.extraUsageLastBillingPeriodKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.extraUsageLastBillingPeriodKey)
            } else {
                defaults.removeObject(forKey: Keys.extraUsageLastBillingPeriodKey)
            }
        }
    }

    // MARK: - Reset

    func resetToDefaults() {
        Self.logger.info("Resetting all preferences to defaults")
        defaults.removeObject(forKey: Keys.warningThreshold)
        defaults.removeObject(forKey: Keys.criticalThreshold)
        defaults.removeObject(forKey: Keys.pollInterval)
        defaults.removeObject(forKey: Keys.launchAtLogin)
        defaults.removeObject(forKey: Keys.dismissedVersion)
        defaults.removeObject(forKey: Keys.dataRetentionDays)
        defaults.removeObject(forKey: Keys.customFiveHourCredits)
        defaults.removeObject(forKey: Keys.customSevenDayCredits)
        defaults.removeObject(forKey: Keys.customMonthlyPrice)
        defaults.removeObject(forKey: Keys.billingCycleDay)
        defaults.removeObject(forKey: Keys.patternNotificationCooldowns)
        defaults.removeObject(forKey: Keys.dismissedPatternFindings)
        defaults.removeObject(forKey: Keys.dismissedTierRecommendation)
        defaults.removeObject(forKey: Keys.extraUsageAlertsEnabled)
        defaults.removeObject(forKey: Keys.extraUsageThreshold50Enabled)
        defaults.removeObject(forKey: Keys.extraUsageThreshold75Enabled)
        defaults.removeObject(forKey: Keys.extraUsageThreshold90Enabled)
        defaults.removeObject(forKey: Keys.extraUsageEnteredAlertEnabled)
        defaults.removeObject(forKey: Keys.extraUsageFiredThresholds)
        defaults.removeObject(forKey: Keys.extraUsageEnteredAlertFired)
        defaults.removeObject(forKey: Keys.extraUsageLastBillingPeriodKey)
    }
}
