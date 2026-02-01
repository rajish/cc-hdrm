import Testing
@testable import cc_hdrm

@Suite("NotificationService Tests")
struct NotificationServiceTests {

    @Test("NotificationService defaults isAuthorized to false")
    @MainActor
    func defaultsIsAuthorizedToFalse() {
        let service = NotificationService()
        #expect(service.isAuthorized == false)
    }

    @Test("NotificationService conforms to NotificationServiceProtocol")
    @MainActor
    func conformsToProtocol() {
        let service = NotificationService()
        let _: any NotificationServiceProtocol = service
        #expect(service.isAuthorized == false)
    }

    @Test("requestAuthorization can be called without crash")
    @MainActor
    func requestAuthorizationNoCrash() async {
        let service = NotificationService()
        await service.requestAuthorization()
        // No crash = pass. isAuthorized depends on system state.
    }

    @Test("MockNotificationService tracks requestAuthorization call count")
    @MainActor
    func mockTracksCallCount() async {
        let mock = MockNotificationService()
        #expect(mock.requestAuthorizationCallCount == 0)
        #expect(mock.isAuthorized == false)

        await mock.requestAuthorization()
        #expect(mock.requestAuthorizationCallCount == 1)

        await mock.requestAuthorization()
        #expect(mock.requestAuthorizationCallCount == 2)
    }
}
