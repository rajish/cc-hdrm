import Foundation
import Testing
@testable import cc_hdrm

// MARK: - Local Mocks for PollingEngine Integration Tests

/// Minimal keychain mock for connectivity notification tests.
private struct CTMockKeychainService: KeychainServiceProtocol {
    let credentials: KeychainCredentials?

    func readCredentials() async throws -> KeychainCredentials {
        guard let credentials else { throw AppError.keychainNotFound }
        return credentials
    }

    func writeCredentials(_ credentials: KeychainCredentials) async throws {
        // No-op for connectivity tests
    }
}

/// Minimal API client mock for connectivity notification tests.
private struct CTMockAPIClient: APIClientProtocol {
    let usageResult: Result<UsageResponse, any Error>

    init(response: UsageResponse) {
        self.usageResult = .success(response)
    }

    init(error: any Error) {
        self.usageResult = .failure(error)
    }

    func fetchUsage(token: String) async throws -> UsageResponse {
        switch usageResult {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    func fetchProfile(token: String) async throws -> ProfileResponse {
        ProfileResponse(organization: nil)
    }
}

/// Minimal token refresh mock for connectivity notification tests.
private struct CTMockTokenRefreshService: TokenRefreshServiceProtocol {
    func refreshToken(using refreshToken: String) async throws -> KeychainCredentials {
        throw AppError.tokenRefreshFailed(underlying: URLError(.badServerResponse))
    }
}

// MARK: - Test Helpers

private func validCredentials() -> KeychainCredentials {
    KeychainCredentials(
        accessToken: "valid-token",
        refreshToken: "refresh-token",
        expiresAt: (Date().timeIntervalSince1970 + 7200) * 1000,
        subscriptionType: "pro",
        rateLimitTier: "tier_1",
        scopes: ["user:inference"]
    )
}

private func successResponse() -> UsageResponse {
    UsageResponse(
        fiveHour: WindowUsage(utilization: 18.0, resetsAt: "2026-01-31T01:59:59.782798+00:00"),
        sevenDay: WindowUsage(utilization: 6.0, resetsAt: "2026-02-06T08:59:59+00:00"),
        sevenDaySonnet: nil,
        extraUsage: nil
    )
}

// MARK: - Connectivity Notification Unit Tests

@Suite("Connectivity Notification Tests")
struct ConnectivityNotificationTests {

    // MARK: - Helpers

    /// Creates an authorized NotificationService with SpyNotificationCenter and optional MockPreferencesManager.
    @MainActor
    private func makeAuthorizedService(
        spy: SpyNotificationCenter = SpyNotificationCenter(),
        prefs: MockPreferencesManager = MockPreferencesManager()
    ) async -> (NotificationService, SpyNotificationCenter, MockPreferencesManager) {
        let service = NotificationService(notificationCenter: spy, preferencesManager: prefs)
        spy.grantAuthorization = true
        await service.requestAuthorization()
        return (service, spy, prefs)
    }

    // MARK: - Threshold: 1 failure → no notification (6.2)

    @Test("1 failure does not trigger outage notification (threshold is 2)")
    @MainActor
    func singleFailureNoNotification() async {
        let (service, spy, _) = await makeAuthorizedService()

        await service.evaluateConnectivity(apiReachable: false)
        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - Threshold: 2 consecutive failures → outage notification (6.3)

    @Test("2 consecutive failures trigger outage notification with correct title/body/identifier")
    @MainActor
    func twoFailuresTriggerOutage() async {
        let (service, spy, _) = await makeAuthorizedService()

        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)

        #expect(spy.addedRequests.count == 1)
        let req = spy.addedRequests[0]
        #expect(req.identifier == "api-outage")
        #expect(req.content.title == "Claude API unreachable")
        #expect(req.content.body == "Monitoring continues — you'll be notified when it recovers")
    }

    // MARK: - Fire-once: 3+ failures → no additional notification (6.4)

    @Test("3+ failures do not send additional notifications (fire-once)")
    @MainActor
    func threeFailuresNoAdditional() async {
        let (service, spy, _) = await makeAuthorizedService()

        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)

        #expect(spy.addedRequests.count == 1) // Only the initial outage notification
    }

    // MARK: - Recovery after outage (6.5)

    @Test("2 failures then success sends recovery notification with correct title/body/identifier")
    @MainActor
    func recoveryAfterOutage() async {
        let (service, spy, _) = await makeAuthorizedService()

        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)
        #expect(spy.addedRequests.count == 1) // outage

        await service.evaluateConnectivity(apiReachable: true)
        #expect(spy.addedRequests.count == 2)
        let req = spy.addedRequests[1]
        #expect(req.identifier == "api-recovered")
        #expect(req.content.title == "Claude API is back")
        #expect(req.content.body == "Service restored — usage data is current")
    }

    // MARK: - Success without prior outage → no recovery notification (6.6)

    @Test("Success without prior outage sends no recovery notification")
    @MainActor
    func successWithoutOutageNoNotification() async {
        let (service, spy, _) = await makeAuthorizedService()

        await service.evaluateConnectivity(apiReachable: true)
        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - isAuthorized = false → no notification (6.7)

    @Test("isAuthorized = false suppresses outage and recovery notifications")
    @MainActor
    func unauthorizedNoNotification() async {
        let spy = SpyNotificationCenter()
        let service = NotificationService(notificationCenter: spy)
        // isAuthorized defaults to false

        // Trigger outage
        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)
        #expect(spy.addedRequests.isEmpty)

        // Trigger recovery
        await service.evaluateConnectivity(apiReachable: true)
        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - apiStatusAlertsEnabled = false → no notification, state still tracks (6.8)

    @Test("apiStatusAlertsEnabled = false suppresses notifications but state still tracks")
    @MainActor
    func disabledAlertsSuppressButTrackState() async {
        let spy = SpyNotificationCenter()
        let prefs = MockPreferencesManager()
        prefs.apiStatusAlertsEnabled = false
        let service = NotificationService(notificationCenter: spy, preferencesManager: prefs)
        spy.grantAuthorization = true
        await service.requestAuthorization()

        // Trigger outage — no notification
        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)
        #expect(spy.addedRequests.isEmpty)

        // Recovery — no notification (outage notification was never delivered)
        await service.evaluateConnectivity(apiReachable: true)
        #expect(spy.addedRequests.isEmpty)

        // Re-enable alerts and trigger new outage — proves state reset correctly
        prefs.apiStatusAlertsEnabled = true
        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)
        #expect(spy.addedRequests.count == 1)
        #expect(spy.addedRequests[0].identifier == "api-outage")
    }

    // MARK: - Toggle apiStatusAlertsEnabled true mid-outage → no retroactive notification (6.9)

    @Test("Toggle apiStatusAlertsEnabled from false to true mid-outage: no retroactive or orphan notification")
    @MainActor
    func toggleEnabledMidOutageNoRetroactive() async {
        let spy = SpyNotificationCenter()
        let prefs = MockPreferencesManager()
        prefs.apiStatusAlertsEnabled = false
        let service = NotificationService(notificationCenter: spy, preferencesManager: prefs)
        spy.grantAuthorization = true
        await service.requestAuthorization()

        // Trigger outage with alerts disabled
        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)
        #expect(spy.addedRequests.isEmpty)

        // Enable alerts mid-outage
        prefs.apiStatusAlertsEnabled = true

        // Another failure — outageDetected is already true, no new notification
        await service.evaluateConnectivity(apiReachable: false)
        #expect(spy.addedRequests.isEmpty)

        // Recovery — no orphan recovery notification (outage was never delivered)
        await service.evaluateConnectivity(apiReachable: true)
        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - After recovery, new outage fires again (6.10)

    @Test("After recovery, a new outage fires outage notification again (re-armed)")
    @MainActor
    func rearmAfterRecovery() async {
        let (service, spy, _) = await makeAuthorizedService()

        // First outage
        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)
        #expect(spy.addedRequests.count == 1)

        // Recovery
        await service.evaluateConnectivity(apiReachable: true)
        #expect(spy.addedRequests.count == 2)

        // Second outage
        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)
        #expect(spy.addedRequests.count == 3)
        #expect(spy.addedRequests[2].identifier == "api-outage")
    }

    // MARK: - Notification identifiers (6.11)

    @Test("Outage notification identifier is 'api-outage', recovery is 'api-recovered'")
    @MainActor
    func notificationIdentifiers() async {
        let (service, spy, _) = await makeAuthorizedService()

        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)
        #expect(spy.addedRequests[0].identifier == "api-outage")

        await service.evaluateConnectivity(apiReachable: true)
        #expect(spy.addedRequests[1].identifier == "api-recovered")
    }

    // MARK: - Interleaved success/failure never reaches threshold (6.12)

    @Test("Interleaved success/failure (success, fail, success, fail) never reaches threshold 2")
    @MainActor
    func interleavedNeverReachesThreshold() async {
        let (service, spy, _) = await makeAuthorizedService()

        await service.evaluateConnectivity(apiReachable: true)
        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: true)
        await service.evaluateConnectivity(apiReachable: false)

        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - Connectivity notifications don't interfere with headroom notifications (6.13)

    @Test("Connectivity notifications use distinct identifiers from headroom notifications")
    @MainActor
    func connectivityDoesNotInterfereWithHeadroom() async {
        let (service, spy, _) = await makeAuthorizedService()

        // Fire a headroom warning first
        let ws = WindowState(utilization: 82, resetsAt: Date().addingTimeInterval(3600))
        await service.evaluateThresholds(fiveHour: ws, sevenDay: nil)
        #expect(spy.addedRequests.count == 1)
        #expect(spy.addedRequests[0].identifier == "headroom-warning-5h")

        // Fire connectivity outage
        await service.evaluateConnectivity(apiReachable: false)
        await service.evaluateConnectivity(apiReachable: false)
        #expect(spy.addedRequests.count == 2)
        #expect(spy.addedRequests[1].identifier == "api-outage")

        // Both notifications coexist — distinct identifiers
        let identifiers = Set(spy.addedRequests.map(\.identifier))
        #expect(identifiers.contains("headroom-warning-5h"))
        #expect(identifiers.contains("api-outage"))
    }
}

// MARK: - PollingEngine Connectivity Integration Tests

@Suite("PollingEngine Connectivity Integration Tests")
struct PollingEngineConnectivityTests {

    // MARK: - Success calls evaluateConnectivity(true) (6.14)

    @Test("PollingEngine calls evaluateConnectivity(apiReachable: true) on successful fetch")
    @MainActor
    func pollingEngineCallsConnectivityOnSuccess() async {
        let mockNotification = MockNotificationService()
        let mockKeychain = CTMockKeychainService(credentials: validCredentials())
        let mockAPI = CTMockAPIClient(response: successResponse())
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: CTMockTokenRefreshService(),
            apiClient: mockAPI,
            appState: appState,
            notificationService: mockNotification
        )

        await engine.performPollCycle()

        #expect(mockNotification.evaluateConnectivityCalls.count == 1)
        #expect(mockNotification.evaluateConnectivityCalls[0] == true)
    }

    // MARK: - Network error calls evaluateConnectivity(false) (6.15)

    @Test("PollingEngine calls evaluateConnectivity(apiReachable: false) on network error")
    @MainActor
    func pollingEngineCallsConnectivityOnNetworkError() async {
        let mockNotification = MockNotificationService()
        let mockKeychain = CTMockKeychainService(credentials: validCredentials())
        let mockAPI = CTMockAPIClient(error: AppError.networkUnreachable)
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: CTMockTokenRefreshService(),
            apiClient: mockAPI,
            appState: appState,
            notificationService: mockNotification
        )

        await engine.performPollCycle()

        #expect(mockNotification.evaluateConnectivityCalls.count == 1)
        #expect(mockNotification.evaluateConnectivityCalls[0] == false)
    }

    // MARK: - 401 does NOT call evaluateConnectivity (6.16)

    @Test("PollingEngine does NOT call evaluateConnectivity on 401 (handled by token refresh)")
    @MainActor
    func pollingEngineNoConnectivityOn401() async {
        let mockNotification = MockNotificationService()
        let mockKeychain = CTMockKeychainService(credentials: validCredentials())
        let mockAPI = CTMockAPIClient(error: AppError.apiError(statusCode: 401, body: "Unauthorized"))
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: CTMockTokenRefreshService(),
            apiClient: mockAPI,
            appState: appState,
            notificationService: mockNotification
        )

        await engine.performPollCycle()

        #expect(mockNotification.evaluateConnectivityCalls.isEmpty)
    }

    // MARK: - Credential error does NOT call evaluateConnectivity (6.17)

    @Test("PollingEngine does NOT call evaluateConnectivity on credential error")
    @MainActor
    func pollingEngineNoConnectivityOnCredentialError() async {
        let mockNotification = MockNotificationService()
        let mockKeychain = CTMockKeychainService(credentials: nil)
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: CTMockTokenRefreshService(),
            apiClient: CTMockAPIClient(response: successResponse()),
            appState: appState,
            notificationService: mockNotification
        )

        await engine.performPollCycle()

        #expect(mockNotification.evaluateConnectivityCalls.isEmpty)
    }

    // MARK: - Parse error calls evaluateConnectivity(false)

    @Test("PollingEngine calls evaluateConnectivity(apiReachable: false) on parse error")
    @MainActor
    func pollingEngineCallsConnectivityOnParseError() async {
        let mockNotification = MockNotificationService()
        let mockKeychain = CTMockKeychainService(credentials: validCredentials())
        let mockAPI = CTMockAPIClient(error: AppError.parseError(underlying: URLError(.cannotParseResponse)))
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: CTMockTokenRefreshService(),
            apiClient: mockAPI,
            appState: appState,
            notificationService: mockNotification
        )

        await engine.performPollCycle()

        #expect(mockNotification.evaluateConnectivityCalls.count == 1)
        #expect(mockNotification.evaluateConnectivityCalls[0] == false)
    }

    // MARK: - 500 server error calls evaluateConnectivity(false)

    @Test("PollingEngine calls evaluateConnectivity(apiReachable: false) on 500 server error")
    @MainActor
    func pollingEngineCallsConnectivityOnServerError() async {
        let mockNotification = MockNotificationService()
        let mockKeychain = CTMockKeychainService(credentials: validCredentials())
        let mockAPI = CTMockAPIClient(error: AppError.apiError(statusCode: 500, body: "Internal Server Error"))
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: CTMockTokenRefreshService(),
            apiClient: mockAPI,
            appState: appState,
            notificationService: mockNotification
        )

        await engine.performPollCycle()

        #expect(mockNotification.evaluateConnectivityCalls.count == 1)
        #expect(mockNotification.evaluateConnectivityCalls[0] == false)
    }
}
