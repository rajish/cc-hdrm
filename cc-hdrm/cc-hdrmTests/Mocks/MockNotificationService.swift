@testable import cc_hdrm

@MainActor
final class MockNotificationService: NotificationServiceProtocol {
    var isAuthorized: Bool = false
    var requestAuthorizationCallCount = 0
    var fiveHourThresholdState: ThresholdState = .aboveWarning
    var sevenDayThresholdState: ThresholdState = .aboveWarning
    var evaluateThresholdsCalls: [(fiveHour: WindowState?, sevenDay: WindowState?)] = []

    func requestAuthorization() async {
        requestAuthorizationCallCount += 1
    }

    func evaluateThresholds(fiveHour: WindowState?, sevenDay: WindowState?) async {
        evaluateThresholdsCalls.append((fiveHour: fiveHour, sevenDay: sevenDay))
    }
}
