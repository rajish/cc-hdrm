import UserNotifications

/// Abstraction over UNUserNotificationCenter for testability.
/// Production code uses UNUserNotificationCenter (conformance below);
/// tests inject a spy to capture delivered notification requests.
@MainActor
protocol NotificationCenterProtocol: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: @preconcurrency NotificationCenterProtocol {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}
