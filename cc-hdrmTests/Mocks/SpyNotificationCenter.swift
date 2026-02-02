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
    /// Authorization status reported by `authorizationStatus()`.
    var stubbedAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - NotificationCenterProtocol

    func authorizationStatus() async -> UNAuthorizationStatus {
        stubbedAuthorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        grantAuthorization
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }
}
