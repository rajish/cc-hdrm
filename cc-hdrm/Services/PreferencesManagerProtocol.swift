import Foundation

/// Default values for all user preferences.
enum PreferencesDefaults {
    static let warningThreshold: Double = 20.0
    static let criticalThreshold: Double = 5.0
    static let pollInterval: TimeInterval = 30
    static let launchAtLogin: Bool = false
}

/// Protocol for the preferences manager that handles reading/writing user preferences.
/// PreferencesManager is the ONLY component that reads/writes UserDefaults for preferences.
protocol PreferencesManagerProtocol: AnyObject {
    var warningThreshold: Double { get set }
    var criticalThreshold: Double { get set }
    var pollInterval: TimeInterval { get set }
    var launchAtLogin: Bool { get set }
    var dismissedVersion: String? { get set }

    func resetToDefaults()
}
