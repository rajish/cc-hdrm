@testable import cc_hdrm

@MainActor
final class MockNotificationService: NotificationServiceProtocol {
    var isAuthorized: Bool = false
    var requestAuthorizationCallCount = 0

    func requestAuthorization() async {
        requestAuthorizationCallCount += 1
    }
}
