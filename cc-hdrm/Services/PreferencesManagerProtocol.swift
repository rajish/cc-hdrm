import Foundation

/// Default values for all user preferences.
enum PreferencesDefaults {
    static let warningThreshold: Double = 20.0
    static let criticalThreshold: Double = 5.0
    static let pollInterval: TimeInterval = 30
    static let launchAtLogin: Bool = false
    static let dataRetentionDays: Int = 365
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

    func resetToDefaults()
}
