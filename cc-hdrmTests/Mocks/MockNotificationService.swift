@testable import cc_hdrm

@MainActor
final class MockNotificationService: NotificationServiceProtocol {
    var isAuthorized: Bool = false
    var requestAuthorizationCallCount = 0
    var fiveHourThresholdState: ThresholdState = .aboveWarning
    var sevenDayThresholdState: ThresholdState = .aboveWarning
    var evaluateThresholdsCalls: [(fiveHour: WindowState?, sevenDay: WindowState?)] = []
    var reevaluateThresholdsCallCount = 0
    var evaluateConnectivityCalls: [Bool] = []

    func requestAuthorization() async {
        requestAuthorizationCallCount += 1
    }

    func evaluateThresholds(fiveHour: WindowState?, sevenDay: WindowState?) async {
        evaluateThresholdsCalls.append((fiveHour: fiveHour, sevenDay: sevenDay))
    }

    func reevaluateThresholds() async {
        reevaluateThresholdsCallCount += 1
    }

    func evaluateConnectivity(apiReachable: Bool) async {
        evaluateConnectivityCalls.append(apiReachable)
    }
}
