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

    // MARK: - Reset

    func resetToDefaults() {
        Self.logger.info("Resetting all preferences to defaults")
        defaults.removeObject(forKey: Keys.warningThreshold)
        defaults.removeObject(forKey: Keys.criticalThreshold)
        defaults.removeObject(forKey: Keys.pollInterval)
        defaults.removeObject(forKey: Keys.launchAtLogin)
        defaults.removeObject(forKey: Keys.dismissedVersion)
    }
}
