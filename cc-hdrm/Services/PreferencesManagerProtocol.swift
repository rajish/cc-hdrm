import Foundation

/// Default values for all user preferences.
enum PreferencesDefaults {
    static let warningThreshold: Double = 20.0
    static let criticalThreshold: Double = 5.0
    static let pollInterval: TimeInterval = 30
    static let launchAtLogin: Bool = false
    static let dataRetentionDays: Int = 365
    static let extraUsageAlertsEnabled: Bool = true
    static let extraUsageThreshold50Enabled: Bool = true
    static let extraUsageThreshold75Enabled: Bool = true
    static let extraUsageThreshold90Enabled: Bool = true
    static let extraUsageEnteredAlertEnabled: Bool = true
}

/// Protocol for the preferences manager that handles reading/writing user preferences.
/// PreferencesManager is the ONLY component that reads/writes UserDefaults for preferences.
protocol PreferencesManagerProtocol: AnyObject {
    var warningThreshold: Double { get set }
    var criticalThreshold: Double { get set }
    var pollInterval: TimeInterval { get set }
    var launchAtLogin: Bool { get set }
    var dismissedVersion: String? { get set }

    /// User-configured data retention period in days. Clamped to 30...1825.
    var dataRetentionDays: Int { get set }

    /// User-configured custom 5-hour credit limit for unknown tiers. Nil if unset.
    var customFiveHourCredits: Int? { get set }
    /// User-configured custom 7-day credit limit for unknown tiers. Nil if unset.
    var customSevenDayCredits: Int? { get set }
    /// User-configured monthly subscription price for custom credit limits. Nil if unset.
    var customMonthlyPrice: Double? { get set }

    /// User-configured billing cycle day (1-28). Nil if unset.
    /// When set, tier recommendations and dollar summaries align to billing cycle boundaries.
    var billingCycleDay: Int? { get set }

    /// Cooldown timestamps for pattern notification delivery. Key is PatternFinding.cooldownKey.
    var patternNotificationCooldowns: [String: Date] { get set }

    /// Set of cooldown keys for pattern findings the user has dismissed in the analytics view.
    var dismissedPatternFindings: Set<String> { get set }

    /// Fingerprint of the last dismissed tier recommendation.
    /// When the current recommendation fingerprint matches, the card stays dismissed.
    var dismissedTierRecommendation: String? { get set }

    // MARK: - Extra Usage Alert Preferences (Story 17.4)

    /// Master toggle for extra usage threshold alerts (default: true).
    var extraUsageAlertsEnabled: Bool { get set }
    /// Toggle for 50% threshold alert (default: true).
    var extraUsageThreshold50Enabled: Bool { get set }
    /// Toggle for 75% threshold alert (default: true).
    var extraUsageThreshold75Enabled: Bool { get set }
    /// Toggle for 90% threshold alert (default: true).
    var extraUsageThreshold90Enabled: Bool { get set }
    /// Toggle for "entered extra usage" alert (default: true).
    var extraUsageEnteredAlertEnabled: Bool { get set }

    // MARK: - Extra Usage Threshold Tracking (Story 17.4)

    /// Set of threshold percentages already fired this billing period (e.g., {50, 75}).
    var extraUsageFiredThresholds: Set<Int> { get set }
    /// Whether "entered extra usage" has fired this billing period.
    var extraUsageEnteredAlertFired: Bool { get set }
    /// Billing period key (e.g., "2026-02") for detecting period reset.
    var extraUsageLastBillingPeriodKey: String? { get set }

    func resetToDefaults()
}
