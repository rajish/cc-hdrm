import Foundation
import Testing
@testable import cc_hdrm

@Suite("Threshold State Machine Tests")
struct ThresholdStateMachineTests {

    // MARK: - Helpers

    /// Creates a WindowState with the given utilization (headroom = 100 - utilization).
    private func windowState(utilization: Double, resetsAt: Date? = Date().addingTimeInterval(3600)) -> WindowState {
        WindowState(utilization: utilization, resetsAt: resetsAt)
    }

    // MARK: - Initial State

    @Test("Initial state is aboveWarning for both windows")
    @MainActor
    func initialState() {
        let service = NotificationService()
        #expect(service.fiveHourThresholdState == .aboveWarning)
        #expect(service.sevenDayThresholdState == .aboveWarning)
    }

    // MARK: - Warning Crossing (AC #1)

    @Test("Headroom drops from 25% to 18% — state becomes warned20")
    @MainActor
    func headroomDropsBelowTwenty() async {
        let service = NotificationService()
        // headroom 18% means utilization 82%
        await service.evaluateThresholds(fiveHour: windowState(utilization: 82), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .warned20)
    }

    // MARK: - Fire-Once Semantics (AC #2)

    @Test("Headroom stays at 15% after warning — no additional state change")
    @MainActor
    func noRepeatedWarning() async {
        let service = NotificationService()
        // First crossing
        await service.evaluateThresholds(fiveHour: windowState(utilization: 82), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .warned20)

        // Still below 20% — state should remain warned20
        await service.evaluateThresholds(fiveHour: windowState(utilization: 85), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .warned20)
    }

    // MARK: - Recovery / Re-arm (AC #4)

    @Test("Headroom recovers to 22% — state resets to aboveWarning")
    @MainActor
    func recoveryRearms() async {
        let service = NotificationService()
        // Cross below 20%
        await service.evaluateThresholds(fiveHour: windowState(utilization: 82), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .warned20)

        // Recover above 20%
        await service.evaluateThresholds(fiveHour: windowState(utilization: 78), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .aboveWarning)
    }

    @Test("After re-arm, headroom drops to 19% — new warning fires (state becomes warned20 again)")
    @MainActor
    func rearmThenNewWarning() async {
        let service = NotificationService()
        // First crossing
        await service.evaluateThresholds(fiveHour: windowState(utilization: 82), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .warned20)

        // Recovery
        await service.evaluateThresholds(fiveHour: windowState(utilization: 78), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .aboveWarning)

        // Second crossing
        await service.evaluateThresholds(fiveHour: windowState(utilization: 81), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .warned20)
    }

    // MARK: - Independent Window Tracking (AC #3)

    @Test("5h and 7d tracked independently — 5h warning doesn't affect 7d state")
    @MainActor
    func independentWindowTracking() async {
        let service = NotificationService()
        // Only 5h crosses threshold
        await service.evaluateThresholds(
            fiveHour: windowState(utilization: 85),
            sevenDay: windowState(utilization: 50) // headroom 50%, well above 20%
        )
        #expect(service.fiveHourThresholdState == .warned20)
        #expect(service.sevenDayThresholdState == .aboveWarning)
    }

    @Test("7d crossing produces warned20 state independently")
    @MainActor
    func sevenDayCrossing() async {
        let service = NotificationService()
        await service.evaluateThresholds(
            fiveHour: windowState(utilization: 50), // headroom 50%
            sevenDay: windowState(utilization: 85)  // headroom 15%
        )
        #expect(service.fiveHourThresholdState == .aboveWarning)
        #expect(service.sevenDayThresholdState == .warned20)
    }

    // MARK: - Unauthorized — No Notification (AC #5)

    @Test("isAuthorized = false — state transition still occurs, no crash")
    @MainActor
    func unauthorizedStillTransitions() async {
        let service = NotificationService()
        // isAuthorized defaults to false
        #expect(service.isAuthorized == false)

        await service.evaluateThresholds(fiveHour: windowState(utilization: 85), sevenDay: nil)
        // State machine still transitions — only notification delivery is skipped
        #expect(service.fiveHourThresholdState == .warned20)
    }

    // MARK: - Nil WindowState

    @Test("nil WindowState — no crash, no state change")
    @MainActor
    func nilWindowStateNoChange() async {
        let service = NotificationService()
        await service.evaluateThresholds(fiveHour: nil, sevenDay: nil)
        #expect(service.fiveHourThresholdState == .aboveWarning)
        #expect(service.sevenDayThresholdState == .aboveWarning)
    }

    // MARK: - Boundary Condition

    @Test("Headroom at exactly 20% does NOT trigger warning (must be strictly below)")
    @MainActor
    func exactTwentyDoesNotTrigger() async {
        let service = NotificationService()
        // headroom = 20% means utilization = 80%
        await service.evaluateThresholds(fiveHour: windowState(utilization: 80), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .aboveWarning)
    }

    // MARK: - Warned5 Transition (State Machine Completeness for Story 5.3)

    @Test("Headroom drops below 5% from warned20 — transitions to warned5")
    @MainActor
    func transitionToWarned5() async {
        let service = NotificationService()
        // Cross below 20%
        await service.evaluateThresholds(fiveHour: windowState(utilization: 82), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .warned20)

        // Drop below 5% (headroom 3% = utilization 97%)
        await service.evaluateThresholds(fiveHour: windowState(utilization: 97), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .warned5)
    }

    @Test("Recovery from warned5 back to aboveWarning when headroom >= 20%")
    @MainActor
    func recoveryFromWarned5() async {
        let service = NotificationService()
        // Cross to warned20
        await service.evaluateThresholds(fiveHour: windowState(utilization: 82), sevenDay: nil)
        // Cross to warned5
        await service.evaluateThresholds(fiveHour: windowState(utilization: 97), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .warned5)

        // Recover above 20%
        await service.evaluateThresholds(fiveHour: windowState(utilization: 75), sevenDay: nil)
        #expect(service.fiveHourThresholdState == .aboveWarning)
    }

    // MARK: - Notification Delivery Verification (H1)

    @Test("Crossing below 20% with isAuthorized=true delivers a notification")
    @MainActor
    func authorizedCrossingDeliversNotification() async {
        let spy = SpyNotificationCenter()
        let service = NotificationService(notificationCenter: spy)
        // Must set isAuthorized — use the spy to grant, then call requestAuthorization
        // Simpler: directly set via the authorize helper
        spy.grantAuthorization = true
        await service.requestAuthorization()

        await service.evaluateThresholds(
            fiveHour: windowState(utilization: 82), // headroom 18%
            sevenDay: nil
        )
        #expect(spy.addedRequests.count == 1)
        #expect(spy.addedRequests[0].identifier == "headroom-warning-5h")
    }

    @Test("Crossing below 20% with isAuthorized=false does NOT deliver notification")
    @MainActor
    func unauthorizedCrossingSkipsDelivery() async {
        let spy = SpyNotificationCenter()
        let service = NotificationService(notificationCenter: spy)
        // isAuthorized defaults to false

        await service.evaluateThresholds(
            fiveHour: windowState(utilization: 82), // headroom 18%
            sevenDay: nil
        )
        #expect(spy.addedRequests.isEmpty)
        // State still transitions
        #expect(service.fiveHourThresholdState == .warned20)
    }

    @Test("No duplicate notification when headroom stays below 20%")
    @MainActor
    func noDuplicateDelivery() async {
        let spy = SpyNotificationCenter()
        let service = NotificationService(notificationCenter: spy)
        spy.grantAuthorization = true
        await service.requestAuthorization()

        await service.evaluateThresholds(fiveHour: windowState(utilization: 82), sevenDay: nil)
        await service.evaluateThresholds(fiveHour: windowState(utilization: 85), sevenDay: nil)
        #expect(spy.addedRequests.count == 1)
    }

    // MARK: - Notification Content Format (M2)

    @Test("Notification content: title is 'cc-hdrm', body contains headroom %, countdown, absolute time")
    @MainActor
    func notificationContentFormat() async {
        let spy = SpyNotificationCenter()
        let service = NotificationService(notificationCenter: spy)
        spy.grantAuthorization = true
        await service.requestAuthorization()

        let resetDate = Date().addingTimeInterval(3600) // 1 hour from now
        await service.evaluateThresholds(
            fiveHour: windowState(utilization: 82, resetsAt: resetDate), // headroom 18%
            sevenDay: nil
        )

        #expect(spy.addedRequests.count == 1)
        let content = spy.addedRequests[0].content
        #expect(content.title == "cc-hdrm")
        #expect(content.body.contains("Claude"))
        #expect(content.body.contains("headroom at 18%"))
        #expect(content.body.contains("resets in"))
        #expect(content.body.contains("at "))
        #expect(content.sound == nil)
    }

    // MARK: - 7d Notification Body Contains "7-day" (M3)

    @Test("7d crossing notification body contains '7-day'")
    @MainActor
    func sevenDayNotificationBodyContains7Day() async {
        let spy = SpyNotificationCenter()
        let service = NotificationService(notificationCenter: spy)
        spy.grantAuthorization = true
        await service.requestAuthorization()

        await service.evaluateThresholds(
            fiveHour: nil,
            sevenDay: windowState(utilization: 85) // headroom 15%
        )

        #expect(spy.addedRequests.count == 1)
        #expect(spy.addedRequests[0].identifier == "headroom-warning-7d")
        #expect(spy.addedRequests[0].content.body.contains("7-day"))
    }

    // MARK: - 5h Notification Body Does NOT Contain "7-day"

    @Test("5h crossing notification body does not contain '7-day'")
    @MainActor
    func fiveHourNotificationBodyOmits7Day() async {
        let spy = SpyNotificationCenter()
        let service = NotificationService(notificationCenter: spy)
        spy.grantAuthorization = true
        await service.requestAuthorization()

        await service.evaluateThresholds(
            fiveHour: windowState(utilization: 85), // headroom 15%
            sevenDay: nil
        )

        #expect(spy.addedRequests.count == 1)
        #expect(!spy.addedRequests[0].content.body.contains("7-day"))
    }

    // MARK: - evaluateWindow Direct Tests (L1)

    @Test("evaluateWindow: aboveWarning + headroom 19.5% → warned20, shouldFire true")
    @MainActor
    func evaluateWindowAboveToWarned() {
        let service = NotificationService()
        let (state, fire) = service.evaluateWindow(currentState: .aboveWarning, headroom: 19.5)
        #expect(state == .warned20)
        #expect(fire == true)
    }

    @Test("evaluateWindow: aboveWarning + headroom 20.0% → aboveWarning, shouldFire false")
    @MainActor
    func evaluateWindowExactTwenty() {
        let service = NotificationService()
        let (state, fire) = service.evaluateWindow(currentState: .aboveWarning, headroom: 20.0)
        #expect(state == .aboveWarning)
        #expect(fire == false)
    }

    @Test("evaluateWindow: warned20 + headroom 4.9% → warned5, shouldFire false")
    @MainActor
    func evaluateWindowWarnedToCritical() {
        let service = NotificationService()
        let (state, fire) = service.evaluateWindow(currentState: .warned20, headroom: 4.9)
        #expect(state == .warned5)
        #expect(fire == false)
    }

    @Test("evaluateWindow: warned5 + headroom 20% → aboveWarning, shouldFire false")
    @MainActor
    func evaluateWindowWarned5Recovery() {
        let service = NotificationService()
        let (state, fire) = service.evaluateWindow(currentState: .warned5, headroom: 20.0)
        #expect(state == .aboveWarning)
        #expect(fire == false)
    }

    // MARK: - Headroom Rounding (H2)

    @Test("Headroom 19.6% rounds to 20 in notification body (not truncated to 19)")
    @MainActor
    func headroomRounding() async {
        let spy = SpyNotificationCenter()
        let service = NotificationService(notificationCenter: spy)
        spy.grantAuthorization = true
        await service.requestAuthorization()

        // utilization 80.4 → headroom 19.6%, rounds to 20
        await service.evaluateThresholds(
            fiveHour: windowState(utilization: 80.4),
            sevenDay: nil
        )

        #expect(spy.addedRequests.count == 1)
        #expect(spy.addedRequests[0].content.body.contains("headroom at 20%"))
    }

    // MARK: - Mock Protocol Conformance

    @Test("MockNotificationService tracks evaluateThresholds calls and exposes threshold states")
    @MainActor
    func mockTracksEvaluateThresholds() async {
        let mock = MockNotificationService()
        #expect(mock.fiveHourThresholdState == .aboveWarning)
        #expect(mock.sevenDayThresholdState == .aboveWarning)
        #expect(mock.evaluateThresholdsCalls.isEmpty)

        let ws = WindowState(utilization: 85, resetsAt: nil)
        await mock.evaluateThresholds(fiveHour: ws, sevenDay: nil)
        #expect(mock.evaluateThresholdsCalls.count == 1)
        #expect(mock.evaluateThresholdsCalls[0].fiveHour?.utilization == 85)
        #expect(mock.evaluateThresholdsCalls[0].sevenDay == nil)
    }
}
