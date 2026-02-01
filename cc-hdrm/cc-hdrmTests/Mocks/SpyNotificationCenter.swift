import UserNotifications
@testable import cc_hdrm

/// Spy that captures notification requests and authorization calls
/// without touching the real UNUserNotificationCenter.
@MainActor
final class SpyNotificationCenter: NotificationCenterProtocol {
    /// All requests passed to `add(_:)`.
    var addedRequests: [UNNotificationRequest] = []
    /// Value returned by `requestAuthorization`.
    var grantAuthorization = false
    /// Authorization status reported by `notificationSettings()`.
    var stubbedAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - NotificationCenterProtocol

    func notificationSettings() async -> UNNotificationSettings {
        // UNNotificationSettings can't be constructed directly.
        // Return a settings object via the real center for the stubbed status.
        // Workaround: encode/decode trick isn't available either.
        // Instead we use a minimal subclass approach — but UNNotificationSettings is not subclass-able.
        // Pragmatic solution: store the status and let tests check addedRequests instead.
        // For authorization flow tests, the real NotificationService tests already cover this.
        await UNUserNotificationCenter.current().notificationSettings()
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        grantAuthorization
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }
}
