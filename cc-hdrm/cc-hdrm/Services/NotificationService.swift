import UserNotifications
import os

@MainActor
final class NotificationService: NotificationServiceProtocol {
    private(set) var isAuthorized: Bool = false
    private let notificationCenter: UNUserNotificationCenter

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "notification"
    )

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

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
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
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
