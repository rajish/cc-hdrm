import UserNotifications
import os

@MainActor
final class NotificationService: NotificationServiceProtocol {
    private(set) var isAuthorized: Bool = false
    private(set) var fiveHourThresholdState: ThresholdState = .aboveWarning
    private(set) var sevenDayThresholdState: ThresholdState = .aboveWarning
    private let notificationCenter: any NotificationCenterProtocol
    private let preferencesManager: any PreferencesManagerProtocol

    /// Tracks last-used thresholds for change detection and re-arming.
    private var lastWarningThreshold: Double
    private var lastCriticalThreshold: Double

    // MARK: - Connectivity State (Story 5.4)
    private var consecutiveFailureCount: Int = 0
    private var outageDetected: Bool = false
    private var outageNotificationDelivered: Bool = false

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "notification"
    )

    init(
        notificationCenter: any NotificationCenterProtocol = UNUserNotificationCenter.current(),
        preferencesManager: any PreferencesManagerProtocol = PreferencesManager()
    ) {
        self.notificationCenter = notificationCenter
        self.preferencesManager = preferencesManager
        self.lastWarningThreshold = preferencesManager.warningThreshold
        self.lastCriticalThreshold = preferencesManager.criticalThreshold
    }

    /// Weak reference to AppState for re-evaluation on threshold change.
    /// Set by AppDelegate after construction.
    weak var appState: AppState?

    // MARK: - Threshold Evaluation

    /// Forces immediate re-evaluation using current AppState headroom values.
    /// Thread-safe: both this method and `evaluateThresholds` (called by PollingEngine)
    /// are `@MainActor`, so calls are serialized — no concurrent execution possible.
    func reevaluateThresholds() async {
        guard let appState else {
            Self.logger.warning("reevaluateThresholds called but appState is nil")
            return
        }
        Self.logger.info("Re-evaluating thresholds after preference change")
        await evaluateThresholds(fiveHour: appState.fiveHour, sevenDay: appState.sevenDay)
    }

    func evaluateThresholds(fiveHour: WindowState?, sevenDay: WindowState?) async {
        let currentWarning = preferencesManager.warningThreshold
        let currentCritical = preferencesManager.criticalThreshold

        // Detect threshold changes and re-arm if headroom is above new thresholds
        if currentWarning != lastWarningThreshold || currentCritical != lastCriticalThreshold {
            Self.logger.info("Thresholds changed: warning \(self.lastWarningThreshold)→\(currentWarning), critical \(self.lastCriticalThreshold)→\(currentCritical)")

            if let fiveHour {
                let headroom = 100.0 - fiveHour.utilization
                if headroom >= currentWarning && (fiveHourThresholdState == .warned20 || fiveHourThresholdState == .warned5) {
                    Self.logger.info("5h re-arming: headroom \(headroom, format: .fixed(precision: 1))% >= new warning \(currentWarning)%")
                    fiveHourThresholdState = .aboveWarning
                }
            }
            if let sevenDay {
                let headroom = 100.0 - sevenDay.utilization
                if headroom >= currentWarning && (sevenDayThresholdState == .warned20 || sevenDayThresholdState == .warned5) {
                    Self.logger.info("7d re-arming: headroom \(headroom, format: .fixed(precision: 1))% >= new warning \(currentWarning)%")
                    sevenDayThresholdState = .aboveWarning
                }
            }

            lastWarningThreshold = currentWarning
            lastCriticalThreshold = currentCritical
        }

        if let fiveHour {
            let headroom = 100.0 - fiveHour.utilization
            let (newState, shouldFireWarning, shouldFireCritical) = evaluateWindow(
                currentState: fiveHourThresholdState,
                headroom: headroom,
                warningThreshold: currentWarning,
                criticalThreshold: currentCritical
            )
            if newState != fiveHourThresholdState {
                Self.logger.info("5h threshold: \(self.fiveHourThresholdState.rawValue, privacy: .public) → \(newState.rawValue, privacy: .public) (headroom \(headroom, format: .fixed(precision: 1))%)")
                fiveHourThresholdState = newState
            }
            if shouldFireWarning {
                await sendNotification(window: "5h", headroom: Int(headroom.rounded()), resetsAt: fiveHour.resetsAt)
            }
            if shouldFireCritical {
                await sendCriticalNotification(window: "5h", headroom: Int(headroom.rounded()), resetsAt: fiveHour.resetsAt)
            }
        }

        if let sevenDay {
            let headroom = 100.0 - sevenDay.utilization
            let (newState, shouldFireWarning, shouldFireCritical) = evaluateWindow(
                currentState: sevenDayThresholdState,
                headroom: headroom,
                warningThreshold: currentWarning,
                criticalThreshold: currentCritical
            )
            if newState != sevenDayThresholdState {
                Self.logger.info("7d threshold: \(self.sevenDayThresholdState.rawValue, privacy: .public) → \(newState.rawValue, privacy: .public) (headroom \(headroom, format: .fixed(precision: 1))%)")
                sevenDayThresholdState = newState
            }
            if shouldFireWarning {
                await sendNotification(window: "7d", headroom: Int(headroom.rounded()), resetsAt: sevenDay.resetsAt)
            }
            if shouldFireCritical {
                await sendCriticalNotification(window: "7d", headroom: Int(headroom.rounded()), resetsAt: sevenDay.resetsAt)
            }
        }
    }

    /// Evaluates a single window's threshold state transition.
    /// Internal (not private) for direct unit-test access.
    func evaluateWindow(
        currentState: ThresholdState,
        headroom: Double,
        warningThreshold: Double = PreferencesDefaults.warningThreshold,
        criticalThreshold: Double = PreferencesDefaults.criticalThreshold
    ) -> (ThresholdState, shouldFireWarning: Bool, shouldFireCritical: Bool) {
        switch currentState {
        case .aboveWarning:
            if headroom < criticalThreshold {
                // Skip warning, go straight to critical
                return (.warned5, shouldFireWarning: false, shouldFireCritical: true)
            }
            if headroom < warningThreshold {
                return (.warned20, shouldFireWarning: true, shouldFireCritical: false)
            }
            return (.aboveWarning, shouldFireWarning: false, shouldFireCritical: false)
        case .warned20:
            if headroom >= warningThreshold {
                return (.aboveWarning, shouldFireWarning: false, shouldFireCritical: false)
            }
            if headroom < criticalThreshold {
                return (.warned5, shouldFireWarning: false, shouldFireCritical: true)
            }
            return (.warned20, shouldFireWarning: false, shouldFireCritical: false)
        case .warned5:
            if headroom >= warningThreshold {
                return (.aboveWarning, shouldFireWarning: false, shouldFireCritical: false)
            }
            return (.warned5, shouldFireWarning: false, shouldFireCritical: false)
        }
    }

    // MARK: - Notification Delivery

    /// Shared delivery method for both warning and critical notifications.
    /// - `sound`: `.default` for critical (5%), `nil` for warning (20%).
    /// - `identifierPrefix`: `"headroom-warning"` or `"headroom-critical"` — distinct
    ///   prefixes ensure critical doesn't replace warning in Notification Center.
    private func deliverNotification(
        window: String,
        headroom: Int,
        resetsAt: Date?,
        sound: UNNotificationSound?,
        identifierPrefix: String
    ) async {
        guard isAuthorized else {
            Self.logger.info("Skipping \(identifierPrefix, privacy: .public) notification — not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "cc-hdrm"

        let windowPrefix = window == "7d" ? "7-day " : ""
        var body = "Claude \(windowPrefix)headroom at \(headroom)%"

        if let resetsAt {
            body += " — resets in \(resetsAt.countdownString()) (\(resetsAt.absoluteTimeString()))"
        }

        content.body = body
        content.sound = sound

        let identifier = "\(identifierPrefix)-\(window)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await notificationCenter.add(request)
            Self.logger.info("\(identifierPrefix, privacy: .public) notification delivered: \(window, privacy: .public) headroom \(headroom)%")
        } catch {
            Self.logger.error("Failed to deliver \(identifierPrefix, privacy: .public) notification: \(error.localizedDescription)")
        }
    }

    private func sendCriticalNotification(window: String, headroom: Int, resetsAt: Date?) async {
        await deliverNotification(
            window: window,
            headroom: headroom,
            resetsAt: resetsAt,
            sound: .default,
            identifierPrefix: "headroom-critical"
        )
    }

    private func sendNotification(window: String, headroom: Int, resetsAt: Date?) async {
        // Intentional: reusing the same identifier per window replaces any
        // undismissed notification instead of stacking duplicates.
        await deliverNotification(
            window: window,
            headroom: headroom,
            resetsAt: resetsAt,
            sound: nil,
            identifierPrefix: "headroom-warning"
        )
    }

    // MARK: - Connectivity Evaluation (Story 5.4)

    func evaluateConnectivity(apiReachable: Bool) async {
        if apiReachable {
            if outageNotificationDelivered {
                await sendConnectivityNotification(
                    title: "Claude API is back",
                    body: "Service restored — usage data is current",
                    identifier: "api-recovered"
                )
            }
            consecutiveFailureCount = 0
            outageDetected = false
            outageNotificationDelivered = false
        } else {
            consecutiveFailureCount += 1
            Self.logger.debug("Consecutive API failure count: \(self.consecutiveFailureCount)")
            if consecutiveFailureCount >= 2 && !outageDetected {
                outageDetected = true
                if await sendConnectivityNotification(
                    title: "Claude API unreachable",
                    body: "Monitoring continues — you'll be notified when it recovers",
                    identifier: "api-outage"
                ) {
                    outageNotificationDelivered = true
                }
            }
        }
    }

    @discardableResult
    private func sendConnectivityNotification(title: String, body: String, identifier: String) async -> Bool {
        guard isAuthorized else {
            Self.logger.info("Skipping connectivity notification — not authorized")
            return false
        }
        guard preferencesManager.apiStatusAlertsEnabled else {
            Self.logger.info("Skipping connectivity notification — API status alerts disabled")
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await notificationCenter.add(request)
            Self.logger.info("Connectivity notification delivered: \(identifier, privacy: .public)")
            return true
        } catch {
            Self.logger.error("Failed to deliver connectivity notification: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let status = await notificationCenter.authorizationStatus()

        switch status {
        case .authorized, .provisional:
            isAuthorized = true
            Self.logger.info("Notification authorization already granted")
            return
        case .denied:
            isAuthorized = false
            Self.logger.info("Notification authorization previously denied by user")
            return
        case .notDetermined:
            break // proceed to request
        case .ephemeral:
            isAuthorized = true
            Self.logger.info("Notification authorization ephemeral")
            return
        @unknown default:
            break // proceed to request
        }

        do {
            let options: UNAuthorizationOptions = [.alert, .sound]
            let granted = try await notificationCenter.requestAuthorization(options: options)
            isAuthorized = granted
            if granted {
                Self.logger.info("Notification authorization granted")
            } else {
                Self.logger.info("Notification authorization denied by user")
            }
        } catch {
            isAuthorized = false
            Self.logger.error("Notification authorization request failed: \(error.localizedDescription)")
        }
    }
}
