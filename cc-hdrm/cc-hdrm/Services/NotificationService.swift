import UserNotifications
import os

@MainActor
final class NotificationService: NotificationServiceProtocol {
    private(set) var isAuthorized: Bool = false
    private(set) var fiveHourThresholdState: ThresholdState = .aboveWarning
    private(set) var sevenDayThresholdState: ThresholdState = .aboveWarning
    private let notificationCenter: any NotificationCenterProtocol

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "notification"
    )

    init(notificationCenter: any NotificationCenterProtocol = UNUserNotificationCenter.current()) {
        self.notificationCenter = notificationCenter
    }

    // MARK: - Threshold Evaluation

    func evaluateThresholds(fiveHour: WindowState?, sevenDay: WindowState?) async {
        if let fiveHour {
            let headroom = 100.0 - fiveHour.utilization
            let (newState, shouldFireWarning, shouldFireCritical) = evaluateWindow(
                currentState: fiveHourThresholdState,
                headroom: headroom
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
                headroom: headroom
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
        headroom: Double
    ) -> (ThresholdState, shouldFireWarning: Bool, shouldFireCritical: Bool) {
        switch currentState {
        case .aboveWarning:
            if headroom < 5 {
                // Skip warning, go straight to critical
                return (.warned5, shouldFireWarning: false, shouldFireCritical: true)
            }
            if headroom < 20 {
                return (.warned20, shouldFireWarning: true, shouldFireCritical: false)
            }
            return (.aboveWarning, shouldFireWarning: false, shouldFireCritical: false)
        case .warned20:
            if headroom >= 20 {
                return (.aboveWarning, shouldFireWarning: false, shouldFireCritical: false)
            }
            if headroom < 5 {
                return (.warned5, shouldFireWarning: false, shouldFireCritical: true)
            }
            return (.warned20, shouldFireWarning: false, shouldFireCritical: false)
        case .warned5:
            if headroom >= 20 {
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

    // MARK: - Authorization

    func requestAuthorization() async {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
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
