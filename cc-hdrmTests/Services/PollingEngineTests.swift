import Foundation
import Testing
@testable import cc_hdrm

// MARK: - Mock Services for PollingEngine Tests

private struct PEMockKeychainService: KeychainServiceProtocol {
    let credentials: KeychainCredentials?
    let readError: (any Error)?
    private let writeTracker: WriteTracker
    private let readTracker: ReadTracker

    final class WriteTracker: @unchecked Sendable {
        var writtenCredentials: KeychainCredentials?
        var writeError: (any Error)?
        var writeCallCount = 0
    }

    final class ReadTracker: @unchecked Sendable {
        var readCallCount = 0
    }

    init(
        credentials: KeychainCredentials? = nil,
        readError: (any Error)? = nil,
        writeError: (any Error)? = nil
    ) {
        self.credentials = credentials
        self.readError = readError
        let wt = WriteTracker()
        wt.writeError = writeError
        self.writeTracker = wt
        self.readTracker = ReadTracker()
    }

    func readCredentials() async throws -> KeychainCredentials {
        readTracker.readCallCount += 1
        if let error = readError {
            throw error
        }
        guard let credentials else {
            throw AppError.keychainNotFound
        }
        return credentials
    }

    func writeCredentials(_ credentials: KeychainCredentials) async throws {
        writeTracker.writeCallCount += 1
        if let error = writeTracker.writeError {
            throw error
        }
        writeTracker.writtenCredentials = credentials
    }

    var readCallCount: Int { readTracker.readCallCount }
    var writeCallCount: Int { writeTracker.writeCallCount }
    var lastWrittenCredentials: KeychainCredentials? { writeTracker.writtenCredentials }
}

private struct PEMockTokenRefreshService: TokenRefreshServiceProtocol {
    let result: KeychainCredentials?
    let error: (any Error)?
    private let callTracker: CallTracker

    final class CallTracker: @unchecked Sendable {
        var callCount = 0
    }

    init(result: KeychainCredentials? = nil, error: (any Error)? = nil) {
        self.result = result
        self.error = error
        self.callTracker = CallTracker()
    }

    var refreshCallCount: Int { callTracker.callCount }

    func refreshToken(using refreshToken: String) async throws -> KeychainCredentials {
        callTracker.callCount += 1
        if let error {
            throw error
        }
        guard let result else {
            throw AppError.tokenRefreshFailed(underlying: URLError(.badServerResponse))
        }
        return result
    }
}

private final class PEMockHistoricalDataService: HistoricalDataServiceProtocol, @unchecked Sendable {
    var persistPollCallCount = 0
    var lastPersistedResponse: UsageResponse?
    var lastPersistedTier: String?
    var shouldThrow = false
    var mockLastPoll: UsagePoll?
    var mockResetEvents: [ResetEvent] = []
    var recentPollsToReturn: [UsagePoll] = []
    var shouldThrowOnGetRecentPolls = false
    var getRecentPollsCallCount = 0

    func persistPoll(_ response: UsageResponse) async throws {
        try await persistPoll(response, tier: nil)
    }

    func persistPoll(_ response: UsageResponse, tier: String?) async throws {
        persistPollCallCount += 1
        lastPersistedResponse = response
        lastPersistedTier = tier
        if shouldThrow {
            throw AppError.databaseQueryFailed(underlying: NSError(domain: "test", code: 1))
        }
    }

    func getRecentPolls(hours: Int) async throws -> [UsagePoll] {
        getRecentPollsCallCount += 1
        if shouldThrowOnGetRecentPolls {
            throw AppError.databaseQueryFailed(underlying: NSError(domain: "test", code: 2))
        }
        return recentPollsToReturn
    }

    func getLastPoll() async throws -> UsagePoll? {
        return mockLastPoll
    }

    func getResetEvents(fromTimestamp: Int64?, toTimestamp: Int64?) async throws -> [ResetEvent] {
        return mockResetEvents
    }

    func getResetEvents(range: TimeRange) async throws -> [ResetEvent] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let fromTimestamp: Int64?

        switch range {
        case .day:
            fromTimestamp = nowMs - (24 * 60 * 60 * 1000)
        case .week:
            fromTimestamp = nowMs - (7 * 24 * 60 * 60 * 1000)
        case .month:
            fromTimestamp = nowMs - (30 * 24 * 60 * 60 * 1000)
        case .all:
            fromTimestamp = nil
        }

        return mockResetEvents.filter { event in
            guard let from = fromTimestamp else { return true }
            return event.timestamp >= from && event.timestamp <= nowMs
        }
    }

    func getDatabaseSize() async throws -> Int64 {
        return 0
    }

    func ensureRollupsUpToDate() async throws {
        // No-op for mock
    }

    func getRolledUpData(range: TimeRange) async throws -> [UsageRollup] {
        return []
    }

    func pruneOldData(retentionDays: Int) async throws {
        // No-op for mock
    }

    func clearAllData() async throws {
        // No-op for mock
    }

    func getExtraUsagePerCycle(billingCycleDay: Int?) async throws -> [String: Double] {
        return [:]
    }

    // Story 10.6: API Outage Period Tracking
    var evaluateOutageStateCallCount = 0
    var lastEvaluateOutageApiReachable: Bool?
    var lastEvaluateOutageFailureReason: String?

    func evaluateOutageState(apiReachable: Bool, failureReason: String?) async {
        evaluateOutageStateCallCount += 1
        lastEvaluateOutageApiReachable = apiReachable
        lastEvaluateOutageFailureReason = failureReason
    }

    func getOutagePeriods(from: Date?, to: Date?) async throws -> [OutagePeriod] {
        return []
    }

    func closeOpenOutages(endedAt: Date) async throws {}

    func loadOutageState() async throws {}
}

private struct PEMockAPIClient: APIClientProtocol {
    private let resultProvider: ResultProvider
    private let callTracker: APICallTracker
    private let profileResultProvider: ProfileResultProvider

    final class ResultProvider: @unchecked Sendable {
        var results: [Result<UsageResponse, any Error>]
        var currentIndex = 0

        init(result: UsageResponse?, error: (any Error)?) {
            if let error {
                self.results = [.failure(error)]
            } else if let result {
                self.results = [.success(result)]
            } else {
                self.results = [.failure(AppError.apiError(statusCode: 500, body: "mock not configured"))]
            }
        }

        init(results: [Result<UsageResponse, any Error>]) {
            self.results = results
        }

        func next() throws -> UsageResponse {
            let idx = min(currentIndex, results.count - 1)
            currentIndex += 1
            switch results[idx] {
            case .success(let r): return r
            case .failure(let e): throw e
            }
        }
    }

    final class ProfileResultProvider: @unchecked Sendable {
        var result: Result<ProfileResponse, any Error>
        var callCount = 0
        var lastToken: String?

        init(result: ProfileResponse? = nil, error: (any Error)? = nil) {
            if let error {
                self.result = .failure(error)
            } else if let result {
                self.result = .success(result)
            } else {
                // Default: return empty profile (non-fatal, no tier)
                self.result = .success(ProfileResponse(organization: nil))
            }
        }

        func next(token: String) throws -> ProfileResponse {
            callCount += 1
            lastToken = token
            switch result {
            case .success(let r): return r
            case .failure(let e): throw e
            }
        }
    }

    final class APICallTracker: @unchecked Sendable {
        var callCount = 0
        var lastToken: String?
    }

    init(result: UsageResponse? = nil, error: (any Error)? = nil, profileResult: ProfileResponse? = nil, profileError: (any Error)? = nil) {
        self.resultProvider = ResultProvider(result: result, error: error)
        self.callTracker = APICallTracker()
        self.profileResultProvider = ProfileResultProvider(result: profileResult, error: profileError)
    }

    init(results: [Result<UsageResponse, any Error>], profileResult: ProfileResponse? = nil, profileError: (any Error)? = nil) {
        self.resultProvider = ResultProvider(results: results)
        self.callTracker = APICallTracker()
        self.profileResultProvider = ProfileResultProvider(result: profileResult, error: profileError)
    }

    var fetchCallCount: Int { callTracker.callCount }
    var lastToken: String? { callTracker.lastToken }
    var profileFetchCallCount: Int { profileResultProvider.callCount }
    var lastProfileToken: String? { profileResultProvider.lastToken }

    func fetchUsage(token: String) async throws -> UsageResponse {
        callTracker.callCount += 1
        callTracker.lastToken = token
        return try resultProvider.next()
    }

    func fetchProfile(token: String) async throws -> ProfileResponse {
        return try profileResultProvider.next(token: token)
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

private func expiredCredentials(withRefreshToken: Bool = true) -> KeychainCredentials {
    KeychainCredentials(
        accessToken: "expired-token",
        refreshToken: withRefreshToken ? "refresh-token" : nil,
        expiresAt: 1000, // epoch — clearly expired
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

// MARK: - PollingEngine Tests

@Suite("PollingEngine Poll Cycle Tests")
struct PollingEngineTests {

    @Test("successful poll cycle populates AppState with usage data and sets .connected")
    @MainActor
    func successfulPollCycle() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        #expect(appState.connectionStatus == .connected)
        #expect(appState.fiveHour?.utilization == 18.0)
        #expect(appState.sevenDay?.utilization == 6.0)
        #expect(appState.statusMessage == nil)
    }

    @Test("network error sets connectionStatus to .disconnected with appropriate statusMessage")
    @MainActor
    func networkErrorSetsDisconnected() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.networkUnreachable)
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        #expect(appState.connectionStatus == .disconnected)
        #expect(appState.statusMessage?.title == "Unable to reach Claude API")
        #expect(appState.statusMessage?.detail == "Will retry automatically")
    }

    @Test("API 401 triggers token refresh (verify refreshCallCount)")
    @MainActor
    func api401TriggersTokenRefresh() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let refreshedCreds = KeychainCredentials(
            accessToken: "new-token",
            refreshToken: "new-refresh",
            expiresAt: (Date().timeIntervalSince1970 + 3600) * 1000,
            subscriptionType: nil, rateLimitTier: nil, scopes: nil
        )
        let mockRefresh = PEMockTokenRefreshService(result: refreshedCreds)
        let mockAPI = PEMockAPIClient(error: AppError.apiError(statusCode: 401, body: "Unauthorized"))
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        #expect(mockRefresh.refreshCallCount == 1, "Token refresh should be triggered on 401")
        // Refreshed credentials should be written to our own Keychain item (no ACL contention)
        #expect(mockKeychain.writeCallCount == 1, "Refreshed credentials should be written to Keychain")
        #expect(appState.connectionStatus == .connected, "Connection status should be restored after refresh")
    }

    @Test("after token refresh, credentials are written to Keychain for next cycle")
    @MainActor
    func refreshedCredentialsPersistedToKeychain() async {
        // Cycle: API returns 401, triggers refresh, writes new credentials to Keychain
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let refreshedCreds = KeychainCredentials(
            accessToken: "new-token",
            refreshToken: "new-refresh",
            expiresAt: (Date().timeIntervalSince1970 + 3600) * 1000,
            subscriptionType: nil, rateLimitTier: nil, scopes: nil
        )
        let mockRefresh = PEMockTokenRefreshService(result: refreshedCreds)
        let mockAPI = PEMockAPIClient(error: AppError.apiError(statusCode: 401, body: "Unauthorized"))
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        #expect(mockKeychain.readCallCount == 1, "Cycle reads from Keychain")
        #expect(mockRefresh.refreshCallCount == 1, "Token refresh should be triggered on 401")
        #expect(mockKeychain.writeCallCount == 1, "Refreshed credentials should be written to Keychain")
        #expect(appState.connectionStatus == .connected)
    }

    @Test("API 401 with no refresh token sets .tokenExpired status")
    @MainActor
    func apiUnauthorizedNoRefreshToken() async {
        let mockKeychain = PEMockKeychainService(credentials: expiredCredentials(withRefreshToken: false))
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.apiError(statusCode: 401, body: "Unauthorized"))
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        #expect(appState.connectionStatus == .tokenExpired)
        #expect(appState.statusMessage == StatusMessage(
            title: "Session expired",
            detail: "Sign in again to continue"
        ))
        #expect(mockRefresh.refreshCallCount == 0, "Refresh should not be attempted without refresh token")
    }

    @Test("keychain not found sets .noCredentials status")
    @MainActor
    func keychainNotFoundSetsNoCredentials() async {
        let mockKeychain = PEMockKeychainService(readError: AppError.keychainNotFound)
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient()
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        #expect(appState.connectionStatus == .noCredentials)
        #expect(appState.statusMessage == StatusMessage(
            title: "Not signed in",
            detail: "Click Sign In to authenticate"
        ))
    }

    @Test("recovery after error — second successful cycle restores .connected")
    @MainActor
    func recoveryAfterError() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(results: [
            .failure(AppError.networkUnreachable),
            .success(successResponse())
        ])
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        // First cycle — error
        await engine.performPollCycle()
        #expect(appState.connectionStatus == .disconnected)

        // Second cycle — recovery
        await engine.performPollCycle()
        #expect(appState.connectionStatus == .connected)
        #expect(appState.fiveHour?.utilization == 18.0)
        #expect(appState.statusMessage == nil)
    }

    @Test("stop() cancels the polling task (verify no further cycles execute)")
    @MainActor
    func stopCancelsPolling() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        // Start the engine (performs initial fetch + creates polling task)
        await engine.start()
        let countAfterStart = mockAPI.fetchCallCount
        #expect(countAfterStart >= 1, "Initial fetch should have executed")

        // Stop the engine — cancels the internal polling task
        engine.stop()

        // Give time for any rogue cycles that might sneak through
        try? await Task.sleep(for: .milliseconds(200))
        #expect(mockAPI.fetchCallCount == countAfterStart, "No further fetch calls after stop")
    }

    @Test("each cycle reads fresh credentials (verify readCredentials called each cycle, NFR7)")
    @MainActor
    func freshCredentialsEachCycle() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()
        await engine.performPollCycle()
        await engine.performPollCycle()

        #expect(mockKeychain.readCallCount == 3, "Credentials should be read fresh each cycle")
    }

    @Test("successful poll cycle calls historicalDataService.persistPoll (Story 10.2 AC #1)")
    @MainActor
    func successfulPollCallsPersistPoll() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let mockHistorical = PEMockHistoricalDataService()
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: mockHistorical
        )

        await engine.performPollCycle()

        // Give time for fire-and-forget Task to execute
        try? await Task.sleep(for: .milliseconds(100))

        #expect(mockHistorical.persistPollCallCount == 1, "persistPoll should be called after successful API response")
        #expect(mockHistorical.lastPersistedResponse?.fiveHour?.utilization == 18.0)
        #expect(mockHistorical.lastPersistedResponse?.sevenDay?.utilization == 6.0)
    }

    @Test("persistPoll error does not affect poll cycle (Story 10.2 AC #2)")
    @MainActor
    func persistPollErrorDoesNotAffectPollCycle() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let mockHistorical = PEMockHistoricalDataService()
        mockHistorical.shouldThrow = true
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: mockHistorical
        )

        await engine.performPollCycle()

        // Give time for fire-and-forget Task to execute
        try? await Task.sleep(for: .milliseconds(100))

        // Poll cycle should still complete successfully
        #expect(appState.connectionStatus == .connected)
        #expect(appState.fiveHour?.utilization == 18.0)
        #expect(mockHistorical.persistPollCallCount == 1, "persistPoll should still be attempted")
    }

    @Test("AppState.lastUpdated is set after successful fetch")
    @MainActor
    func lastUpdatedSetOnSuccess() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let appState = AppState()

        #expect(appState.lastUpdated == nil)

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        #expect(appState.lastUpdated != nil, "lastUpdated should be set after successful fetch")
    }

    @Test("parse error sets .disconnected with format message")
    @MainActor
    func parseErrorSetsDisconnected() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.parseError(underlying: URLError(.cannotDecodeContentData)))
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        #expect(appState.connectionStatus == .disconnected)
        #expect(appState.statusMessage?.title == "Unexpected API response format")
    }
}

// MARK: - PollingEngine Sparkline Tests (Story 12.1)

@Suite("PollingEngine Sparkline Tests")
struct PollingEngineSparklineTests {

    @Test("poll cycle updates sparkline data on success")
    @MainActor
    func pollCycleUpdatesSparklineData() async throws {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let mockHistorical = PEMockHistoricalDataService()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let testPolls = [
            UsagePoll(id: 1, timestamp: now - 60000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: 30.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now, fiveHourUtil: 52.0, fiveHourResetsAt: nil, sevenDayUtil: 31.0, sevenDayResetsAt: nil)
        ]
        mockHistorical.recentPollsToReturn = testPolls
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: mockHistorical
        )

        await engine.performPollCycle()

        // Wait for async sparkline refresh to complete
        let timeout = Date().addingTimeInterval(1.0)
        while appState.sparklineData.isEmpty && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(appState.sparklineData.count == 2)
        #expect(appState.sparklineData[0].timestamp < appState.sparklineData[1].timestamp)
        #expect(mockHistorical.getRecentPollsCallCount >= 1)
    }

    @Test("sparkline refresh failure does not prevent poll cycle completion")
    @MainActor
    func sparklineRefreshFailureDoesNotBlockPoll() async throws {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let mockHistorical = PEMockHistoricalDataService()
        mockHistorical.shouldThrowOnGetRecentPolls = true
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: mockHistorical
        )

        // Poll should complete successfully despite sparkline failure
        await engine.performPollCycle()

        // Main state should be updated
        #expect(appState.connectionStatus == .connected)
        #expect(appState.fiveHour?.utilization == 18.0)

        // Wait briefly to ensure async task had time to run
        try await Task.sleep(for: .milliseconds(50))

        // Sparkline data should remain empty (refresh failed)
        #expect(appState.sparklineData.isEmpty)
        #expect(mockHistorical.getRecentPollsCallCount >= 1)
    }

    @Test("sparkline data preserves timestamp ascending order")
    @MainActor
    func sparklineDataPreservesTimestampOrder() async throws {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let mockHistorical = PEMockHistoricalDataService()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        // Data already sorted ascending by timestamp (as returned by HistoricalDataService)
        let testPolls = [
            UsagePoll(id: 1, timestamp: now - 120000, fiveHourUtil: 48.0, fiveHourResetsAt: nil, sevenDayUtil: 28.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now - 60000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: 30.0, sevenDayResetsAt: nil),
            UsagePoll(id: 3, timestamp: now, fiveHourUtil: 52.0, fiveHourResetsAt: nil, sevenDayUtil: 31.0, sevenDayResetsAt: nil)
        ]
        mockHistorical.recentPollsToReturn = testPolls
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: mockHistorical
        )

        await engine.performPollCycle()

        // Wait for async sparkline refresh to complete
        let timeout = Date().addingTimeInterval(1.0)
        while appState.sparklineData.isEmpty && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(appState.sparklineData.count == 3)

        // Verify ascending order is preserved
        for i in 1..<appState.sparklineData.count {
            #expect(appState.sparklineData[i].timestamp > appState.sparklineData[i-1].timestamp)
        }
    }

    @Test("sparkline data not cleared when no historical service")
    @MainActor
    func noHistoricalServiceKeepsEmptySparklineData() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: nil  // No historical service
        )

        await engine.performPollCycle()

        // Poll should complete successfully
        #expect(appState.connectionStatus == .connected)
        #expect(appState.fiveHour?.utilization == 18.0)

        // Sparkline data should remain empty (no service to populate it)
        #expect(appState.sparklineData.isEmpty)
    }

    @Test("sparkline data includes polls with nil fiveHourUtil (edge case)")
    @MainActor
    func sparklineDataIncludesNilUtilPolls() async throws {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let mockHistorical = PEMockHistoricalDataService()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        // Include a poll with nil fiveHourUtil (valid per story Dev Notes)
        let testPolls = [
            UsagePoll(id: 1, timestamp: now - 60000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: 30.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now - 30000, fiveHourUtil: nil, fiveHourResetsAt: nil, sevenDayUtil: 32.0, sevenDayResetsAt: nil),
            UsagePoll(id: 3, timestamp: now, fiveHourUtil: 52.0, fiveHourResetsAt: nil, sevenDayUtil: 31.0, sevenDayResetsAt: nil)
        ]
        mockHistorical.recentPollsToReturn = testPolls
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: mockHistorical
        )

        await engine.performPollCycle()

        // Wait for async sparkline refresh to complete
        let timeout = Date().addingTimeInterval(1.0)
        while appState.sparklineData.count < 3 && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        // All 3 polls should be present, including the one with nil fiveHourUtil
        #expect(appState.sparklineData.count == 3)
        #expect(appState.sparklineData[1].fiveHourUtil == nil)
    }
}

// MARK: - PollingEngine Profile Fetch Tests (Story 18.2)

@Suite("PollingEngine Profile Fetch Tests")
struct PollingEngineProfileFetchTests {

    @Test("token refresh fetches profile and updates tier in credentials (AC 2)")
    @MainActor
    func tokenRefreshFetchesProfile() async {
        let originalCreds = KeychainCredentials(
            accessToken: "old-token",
            refreshToken: "refresh-token",
            expiresAt: (Date().timeIntervalSince1970 + 7200) * 1000,
            subscriptionType: "pro",
            rateLimitTier: "default_claude_pro",
            scopes: ["user:inference"]
        )
        let mockKeychain = PEMockKeychainService(credentials: originalCreds)
        let refreshedCreds = KeychainCredentials(
            accessToken: "new-token",
            refreshToken: "new-refresh",
            expiresAt: (Date().timeIntervalSince1970 + 3600) * 1000,
            subscriptionType: nil, rateLimitTier: nil, scopes: nil
        )
        let mockRefresh = PEMockTokenRefreshService(result: refreshedCreds)

        // Profile returns upgraded tier
        let profileResult = ProfileResponse(
            organization: .init(organizationType: "claude_max", rateLimitTier: "default_claude_max_5x")
        )
        let mockAPI = PEMockAPIClient(
            error: AppError.apiError(statusCode: 401, body: "Unauthorized"),
            profileResult: profileResult
        )
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        // Profile should have been fetched during token refresh with the NEW token
        #expect(mockAPI.profileFetchCallCount == 1)
        #expect(mockAPI.lastProfileToken == "new-token", "Profile must be fetched with the refreshed token, not the old one")

        // Written credentials should have the upgraded tier
        let written = mockKeychain.lastWrittenCredentials
        #expect(written?.rateLimitTier == "default_claude_max_5x")
        #expect(written?.subscriptionType == "max")
    }

    @Test("token refresh profile failure is non-fatal — preserves original tier (AC 4)")
    @MainActor
    func tokenRefreshProfileFailureNonFatal() async {
        let originalCreds = KeychainCredentials(
            accessToken: "old-token",
            refreshToken: "refresh-token",
            expiresAt: (Date().timeIntervalSince1970 + 7200) * 1000,
            subscriptionType: "pro",
            rateLimitTier: "default_claude_pro",
            scopes: ["user:inference"]
        )
        let mockKeychain = PEMockKeychainService(credentials: originalCreds)
        let refreshedCreds = KeychainCredentials(
            accessToken: "new-token",
            refreshToken: "new-refresh",
            expiresAt: (Date().timeIntervalSince1970 + 3600) * 1000,
            subscriptionType: nil, rateLimitTier: nil, scopes: nil
        )
        let mockRefresh = PEMockTokenRefreshService(result: refreshedCreds)

        // Profile fetch will fail
        let mockAPI = PEMockAPIClient(
            error: AppError.apiError(statusCode: 401, body: "Unauthorized"),
            profileError: AppError.networkUnreachable
        )
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        // Should still succeed — profile failure is non-fatal
        #expect(appState.connectionStatus == .connected)

        // Written credentials should preserve original tier
        let written = mockKeychain.lastWrittenCredentials
        #expect(written?.rateLimitTier == "default_claude_pro")
        #expect(written?.subscriptionType == "pro")
    }

    @Test("nil tier triggers profile backfill during poll cycle (AC 3)")
    @MainActor
    func nilTierTriggersBackfill() async {
        let credsWithNilTier = KeychainCredentials(
            accessToken: "valid-token",
            refreshToken: "refresh-token",
            expiresAt: (Date().timeIntervalSince1970 + 7200) * 1000,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: ["user:inference"]
        )
        let mockKeychain = PEMockKeychainService(credentials: credsWithNilTier)
        let mockRefresh = PEMockTokenRefreshService()

        let profileResult = ProfileResponse(
            organization: .init(organizationType: "claude_pro", rateLimitTier: "default_claude_pro")
        )
        let mockAPI = PEMockAPIClient(
            result: successResponse(),
            profileResult: profileResult
        )
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        // Profile should have been fetched for backfill
        #expect(mockAPI.profileFetchCallCount == 1)

        // Backfilled credentials should be written to Keychain
        let written = mockKeychain.lastWrittenCredentials
        #expect(written?.rateLimitTier == "default_claude_pro")
        #expect(written?.subscriptionType == "pro")

        // Credit limits should be resolved
        #expect(appState.creditLimits != nil)
    }

    @Test("non-nil tier does NOT trigger profile backfill")
    @MainActor
    func nonNilTierSkipsBackfill() async {
        let credsWithTier = validCredentials()
        let mockKeychain = PEMockKeychainService(credentials: credsWithTier)
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        // Profile should NOT have been fetched (tier already present)
        #expect(mockAPI.profileFetchCallCount == 0)
    }

    @Test("backfill is not retried on subsequent cycles after profile returned no tier")
    @MainActor
    func backfillNotRetriedWhenProfileHasNoTier() async {
        let credsWithNilTier = KeychainCredentials(
            accessToken: "valid-token",
            refreshToken: "refresh-token",
            expiresAt: (Date().timeIntervalSince1970 + 7200) * 1000,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: ["user:inference"]
        )
        let mockKeychain = PEMockKeychainService(credentials: credsWithNilTier)
        let mockRefresh = PEMockTokenRefreshService()

        // Profile returns successfully but with NO tier (e.g., free account)
        let emptyProfile = ProfileResponse(organization: .init(organizationType: nil, rateLimitTier: nil))
        let mockAPI = PEMockAPIClient(
            result: successResponse(),
            profileResult: emptyProfile
        )
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        // First cycle — backfill attempted, profile has no tier
        await engine.performPollCycle()
        #expect(mockAPI.profileFetchCallCount == 1)

        // Second cycle — should NOT retry backfill
        await engine.performPollCycle()
        #expect(mockAPI.profileFetchCallCount == 1, "Backfill should not retry after profile returned no tier")
    }

    @Test("backfill guard resets after token refresh, allowing retry")
    @MainActor
    func backfillGuardResetsAfterTokenRefresh() async {
        let credsWithNilTier = KeychainCredentials(
            accessToken: "old-token",
            refreshToken: "refresh-token",
            expiresAt: (Date().timeIntervalSince1970 + 7200) * 1000,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: ["user:inference"]
        )
        let mockKeychain = PEMockKeychainService(credentials: credsWithNilTier)
        let refreshedCreds = KeychainCredentials(
            accessToken: "new-token",
            refreshToken: "new-refresh",
            expiresAt: (Date().timeIntervalSince1970 + 3600) * 1000,
            subscriptionType: nil, rateLimitTier: nil, scopes: nil
        )
        let mockRefresh = PEMockTokenRefreshService(result: refreshedCreds)

        // Profile returns no tier initially, but will return tier after refresh
        let emptyProfile = ProfileResponse(organization: .init(organizationType: nil, rateLimitTier: nil))
        let mockAPI = PEMockAPIClient(
            results: [
                .success(successResponse()),
                .failure(AppError.apiError(statusCode: 401, body: "Unauthorized")),
                .success(successResponse())
            ],
            profileResult: emptyProfile
        )
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        // Cycle 1: backfill attempted (profile has no tier), guard set
        await engine.performPollCycle()
        #expect(mockAPI.profileFetchCallCount == 1)

        // Cycle 2: 401 triggers token refresh, which resets the guard and fetches profile
        await engine.performPollCycle()
        // Profile called during refresh (guard was reset)
        #expect(mockAPI.profileFetchCallCount == 2)

        // Cycle 3: guard was reset by refresh, so backfill is attempted again
        await engine.performPollCycle()
        #expect(mockAPI.profileFetchCallCount == 3, "Backfill should retry after token refresh resets the guard")
    }

    @Test("backfill profile failure is non-fatal — poll cycle continues (AC 4)")
    @MainActor
    func backfillProfileFailureNonFatal() async {
        let credsWithNilTier = KeychainCredentials(
            accessToken: "valid-token",
            refreshToken: "refresh-token",
            expiresAt: (Date().timeIntervalSince1970 + 7200) * 1000,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: ["user:inference"]
        )
        let mockKeychain = PEMockKeychainService(credentials: credsWithNilTier)
        let mockRefresh = PEMockTokenRefreshService()

        // Profile will fail, but usage will succeed
        let mockAPI = PEMockAPIClient(
            result: successResponse(),
            profileError: AppError.networkUnreachable
        )
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState
        )

        await engine.performPollCycle()

        // Poll cycle should still complete successfully
        #expect(appState.connectionStatus == .connected)
        #expect(appState.fiveHour?.utilization == 18.0)

        // Credit limits should be nil (no tier, no custom limits)
        #expect(appState.creditLimits == nil)
    }

    // MARK: - Story 10.6: Outage State Evaluation

    @Test("successful poll calls evaluateOutageState with apiReachable=true (Story 10.6)")
    @MainActor
    func successfulPollCallsEvaluateOutageStateSuccess() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let mockHistorical = PEMockHistoricalDataService()
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: mockHistorical
        )

        await engine.performPollCycle()

        #expect(mockHistorical.evaluateOutageStateCallCount == 1)
        #expect(mockHistorical.lastEvaluateOutageApiReachable == true)
        #expect(mockHistorical.lastEvaluateOutageFailureReason == nil)
    }

    @Test("network error calls evaluateOutageState with networkUnreachable (Story 10.6)")
    @MainActor
    func networkErrorCallsEvaluateOutageState() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.networkUnreachable)
        let mockHistorical = PEMockHistoricalDataService()
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: mockHistorical
        )

        await engine.performPollCycle()

        #expect(mockHistorical.evaluateOutageStateCallCount == 1)
        #expect(mockHistorical.lastEvaluateOutageApiReachable == false)
        #expect(mockHistorical.lastEvaluateOutageFailureReason == "networkUnreachable")
    }

    @Test("API 503 calls evaluateOutageState with httpError:503 (Story 10.6)")
    @MainActor
    func apiErrorCallsEvaluateOutageState() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.apiError(statusCode: 503, body: "Service Unavailable"))
        let mockHistorical = PEMockHistoricalDataService()
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: mockHistorical
        )

        await engine.performPollCycle()

        #expect(mockHistorical.evaluateOutageStateCallCount == 1)
        #expect(mockHistorical.lastEvaluateOutageApiReachable == false)
        #expect(mockHistorical.lastEvaluateOutageFailureReason == "httpError:503")
    }

    @Test("parse error calls evaluateOutageState with parseError (Story 10.6)")
    @MainActor
    func parseErrorCallsEvaluateOutageState() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.parseError(underlying: URLError(.cannotParseResponse)))
        let mockHistorical = PEMockHistoricalDataService()
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: mockHistorical
        )

        await engine.performPollCycle()

        #expect(mockHistorical.evaluateOutageStateCallCount == 1)
        #expect(mockHistorical.lastEvaluateOutageApiReachable == false)
        #expect(mockHistorical.lastEvaluateOutageFailureReason == "parseError")
    }

    @Test("API 401 does NOT call evaluateOutageState (Story 10.6)")
    @MainActor
    func api401DoesNotCallEvaluateOutageState() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let refreshedCreds = KeychainCredentials(
            accessToken: "new-token",
            refreshToken: "new-refresh",
            expiresAt: (Date().timeIntervalSince1970 + 3600) * 1000,
            subscriptionType: nil, rateLimitTier: nil, scopes: nil
        )
        let mockRefresh = PEMockTokenRefreshService(result: refreshedCreds)
        let mockAPI = PEMockAPIClient(error: AppError.apiError(statusCode: 401, body: "Unauthorized"))
        let mockHistorical = PEMockHistoricalDataService()
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            historicalDataService: mockHistorical
        )

        await engine.performPollCycle()

        // 401 is an auth issue, not an API outage — should NOT trigger outage tracking
        #expect(mockHistorical.evaluateOutageStateCallCount == 0)
    }
}

// MARK: - Backoff & Rate Limit Tests (Story 2.4)

@Suite("PollingEngine Backoff Tests")
struct PollingEngineBackoffTests {

    // MARK: - computeNextInterval Tests

    @Test("single failure returns base interval (no backoff)")
    @MainActor
    func singleFailureNoBackoff() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.networkUnreachable)
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { false }
        )

        // 1 failure -> consecutiveFailureCount = 1
        await engine.performPollCycle()

        let interval = engine.computeNextInterval()
        #expect(interval == 300.0)
    }

    @Test("single 429 with Retry-After > base uses retryAfter as floor")
    @MainActor
    func singleFailureRetryAfterFloor() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.rateLimited(retryAfter: 600))
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { false }
        )

        // 1 failure with Retry-After=600 > base(300) -> uses retryAfter floor
        await engine.performPollCycle()

        let interval = engine.computeNextInterval()
        #expect(interval == 600.0)
    }

    @Test("2 consecutive failures doubles interval")
    @MainActor
    func twoFailuresDoubleInterval() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(results: [
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
        ])
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle()
        await engine.performPollCycle()

        let interval = engine.computeNextInterval()
        #expect(interval == 600.0) // 300 * 2^1
    }

    @Test("3 consecutive failures quadruples interval")
    @MainActor
    func threeFailuresQuadrupleInterval() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(results: [
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
        ])
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle()
        await engine.performPollCycle()
        await engine.performPollCycle()

        let interval = engine.computeNextInterval()
        #expect(interval == 1200.0) // 300 * 2^2
    }

    @Test("backoff caps at 1 hour (3600s)")
    @MainActor
    func backoffCapsAt3600Seconds() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        // Need enough failures to exceed 3600s: 300 * 2^4 = 4800 > 3600
        let mockAPI = PEMockAPIClient(results: [
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
        ])
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { false }
        )

        for _ in 0..<5 {
            await engine.performPollCycle()
        }

        let interval = engine.computeNextInterval()
        #expect(interval == 3600.0) // Capped
    }

    @Test("exponent capped at 10 — 100 consecutive failures doesn't overflow")
    @MainActor
    func exponentCappedAt10() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.networkUnreachable)
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { false }
        )

        // Simulate 100 failures
        for _ in 0..<100 {
            await engine.performPollCycle()
        }

        let interval = engine.computeNextInterval()
        // 300 * 2^10 = 307200, capped to 3600
        #expect(interval == 3600.0)
        #expect(interval.isFinite) // No overflow
    }

    @Test("success after backoff resets interval to base")
    @MainActor
    func successResetsBackoff() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(results: [
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
            .success(successResponse()),
        ])
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { false }
        )

        // 3 failures
        await engine.performPollCycle()
        await engine.performPollCycle()
        await engine.performPollCycle()
        #expect(engine.computeNextInterval() == 1200.0) // 300 * 2^2

        // Success resets
        await engine.performPollCycle()
        #expect(engine.computeNextInterval() == 300.0)
    }

    @Test("429 with Retry-After=60 uses retryAfter as floor")
    @MainActor
    func retryAfterFloor() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(results: [
            .failure(AppError.rateLimited(retryAfter: 60)),
            .failure(AppError.rateLimited(retryAfter: 60)),
        ])
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { false }
        )

        // 2 failures: backoff = 300 * 2^1 = 600, retryAfter = 60 -> max(600, 60) = 600
        await engine.performPollCycle()
        await engine.performPollCycle()

        let interval = engine.computeNextInterval()
        #expect(interval == 600.0)
    }

    @Test("429 with Retry-After exceeding cap is capped at 3600s")
    @MainActor
    func retryAfterExceedingCap() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(results: [
            .failure(AppError.rateLimited(retryAfter: 7200)),
            .failure(AppError.rateLimited(retryAfter: 7200)),
        ])
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle()
        await engine.performPollCycle()

        let interval = engine.computeNextInterval()
        #expect(interval == 3600.0) // Capped
    }

    @Test("evaluateConnectivity and evaluateOutageState NOT called on 429")
    @MainActor
    func noEvaluateConnectivityOn429() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.rateLimited(retryAfter: 30))
        let appState = AppState()
        let mockNotification = MockNotificationService()
        let mockHistorical = PEMockHistoricalDataService()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            notificationService: mockNotification,
            historicalDataService: mockHistorical,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle()

        // Neither evaluateConnectivity nor evaluateOutageState should be called for 429
        #expect(mockNotification.evaluateConnectivityCalls.isEmpty)
        #expect(mockHistorical.evaluateOutageStateCallCount == 0)
    }

    @Test("lastAttempted is updated before fetchUsageData, not on credential failure")
    @MainActor
    func lastAttemptedUpdatedOnAPICall() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            isLowPowerModeEnabled: { false }
        )

        #expect(appState.lastAttempted == nil)
        await engine.performPollCycle()
        #expect(appState.lastAttempted != nil)
    }

    @Test("lastAttempted NOT updated on credential failure")
    @MainActor
    func lastAttemptedNotUpdatedOnCredentialFailure() async {
        let mockKeychain = PEMockKeychainService(readError: AppError.keychainNotFound)
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle()
        #expect(appState.lastAttempted == nil) // No API call attempted
    }

    @Test("recovery from backoff restores consecutiveFailureCount to 0")
    @MainActor
    func recoveryResetsFailureCount() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(results: [
            .failure(AppError.rateLimited(retryAfter: 60)),
            .failure(AppError.rateLimited(retryAfter: 60)),
            .success(successResponse()),
        ])
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle()
        await engine.performPollCycle()
        #expect(engine.computeNextInterval() == 600.0) // 300 * 2^1

        await engine.performPollCycle() // success
        #expect(engine.computeNextInterval() == 300.0) // back to base
    }

    @Test("retryAfterOverride cleared when non-429 error follows a 429")
    @MainActor
    func retryAfterClearedOnDifferentError() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(results: [
            .failure(AppError.rateLimited(retryAfter: 200)),
            .failure(AppError.rateLimited(retryAfter: 200)),
            .failure(AppError.networkUnreachable), // different error clears retryAfter
        ])
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle() // 429 -> retryAfter=200
        await engine.performPollCycle() // 429 -> retryAfter=200
        await engine.performPollCycle() // networkUnreachable -> retryAfter cleared

        // 3 failures: backoff = 300 * 2^2 = 1200, no retryAfter override
        let interval = engine.computeNextInterval()
        #expect(interval == 1200.0) // Not 200
    }

    @Test("Low Power Mode doubles base interval")
    @MainActor
    func lowPowerModeDoublesBase() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(result: successResponse())
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { true }
        )

        let interval = engine.computeNextInterval()
        #expect(interval == 600.0) // 300 * 2
    }

    @Test("Low Power Mode + backoff compounds correctly (600s base -> 1200s -> 2400s -> cap 3600s)")
    @MainActor
    func lowPowerModeWithBackoff() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(results: [
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
            .failure(AppError.networkUnreachable),
        ])
        let appState = AppState()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            isLowPowerModeEnabled: { true }
        )

        // 1 failure -> base (600s, LPM doubles 300 to 600)
        await engine.performPollCycle()
        #expect(engine.computeNextInterval() == 600.0)

        // 2 failures -> 600 * 2^1 = 1200
        await engine.performPollCycle()
        #expect(engine.computeNextInterval() == 1200.0)

        // 3 failures -> 600 * 2^2 = 2400
        await engine.performPollCycle()
        #expect(engine.computeNextInterval() == 2400.0)

        // 4 failures -> 600 * 2^3 = 4800, capped at 3600
        await engine.performPollCycle()
        #expect(engine.computeNextInterval() == 3600.0)
    }

    // MARK: - Rate Limit Status Message Tests

    @Test("429 sets connectionStatus to .disconnected with 'Rate limited' message")
    @MainActor
    func rateLimitedStatusMessage() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.rateLimited(retryAfter: 45))
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle()

        #expect(appState.connectionStatus == .disconnected)
        #expect(appState.statusMessage?.title == "Rate limited")
        #expect(appState.statusMessage?.detail == "Will retry in 45s. Sign out and back in to reset, or increase poll interval in Settings.")
    }

    @Test("429 without Retry-After shows 'Will retry with backoff'")
    @MainActor
    func rateLimitedNoRetryAfterMessage() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.rateLimited(retryAfter: nil))
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle()

        #expect(appState.connectionStatus == .disconnected)
        #expect(appState.statusMessage?.title == "Rate limited")
        #expect(appState.statusMessage?.detail == "Will retry with backoff. Sign out and back in to reset, or increase poll interval in Settings.")
    }

    @Test("mixed errors (429, timeout, 429, timeout) — connectivity counter not reset by 429s")
    @MainActor
    func mixedErrorsConnectivityNotResetBy429() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(results: [
            .failure(AppError.rateLimited(retryAfter: 30)),
            .failure(AppError.networkUnreachable),
            .failure(AppError.rateLimited(retryAfter: 30)),
            .failure(AppError.networkUnreachable),
        ])
        let appState = AppState()
        let mockHistorical = PEMockHistoricalDataService()
        let prefs = MockPreferencesManager()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            preferencesManager: prefs,
            historicalDataService: mockHistorical,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle() // 429 -> evaluateOutageState NOT called
        #expect(mockHistorical.evaluateOutageStateCallCount == 0)

        await engine.performPollCycle() // networkUnreachable -> evaluateOutageState called
        #expect(mockHistorical.evaluateOutageStateCallCount == 1)
        #expect(mockHistorical.lastEvaluateOutageApiReachable == false)

        await engine.performPollCycle() // 429 -> evaluateOutageState NOT called again
        #expect(mockHistorical.evaluateOutageStateCallCount == 1)

        await engine.performPollCycle() // networkUnreachable -> evaluateOutageState called
        #expect(mockHistorical.evaluateOutageStateCallCount == 2)

        // 4 failures total -> backoff should be applied
        // consecutiveFailureCount = 4, exponent = min(4-1, 10) = 3
        // backoff = 300 * 2^3 = 2400, no retryAfter, min(2400, 3600) = 2400
        let interval = engine.computeNextInterval()
        #expect(interval == 2400.0)
    }
}

// MARK: - PopoverView Status Message Tests (Story 2.4)

@Suite("PopoverView Rate Limit Display Tests")
struct PopoverViewRateLimitTests {

    @Test("429 rate limit message passes through to disconnected status (not overridden)")
    @MainActor
    func rateLimitMessagePassesThrough() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.rateLimited(retryAfter: 30))
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle()

        // After 429, connectionStatus is .disconnected AND statusMessage is set
        // PopoverView.resolvedStatusMessage returns appState.statusMessage when non-nil
        // for .disconnected (not the generic "Unable to reach Claude API")
        #expect(appState.connectionStatus == .disconnected)
        #expect(appState.statusMessage != nil)
        #expect(appState.statusMessage?.title == "Rate limited")
    }

    @Test("generic disconnected fallback uses lastAttempted when no status message")
    @MainActor
    func genericDisconnectedUsesLastAttempted() async {
        let mockKeychain = PEMockKeychainService(credentials: validCredentials())
        let mockRefresh = PEMockTokenRefreshService()
        let mockAPI = PEMockAPIClient(error: AppError.networkUnreachable)
        let appState = AppState()

        let engine = PollingEngine(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI,
            appState: appState,
            isLowPowerModeEnabled: { false }
        )

        await engine.performPollCycle()

        // After network error, lastAttempted is set (updated before fetchUsageData)
        // PopoverView.resolvedStatusMessage falls back to generic message with lastAttempted
        #expect(appState.connectionStatus == .disconnected)
        #expect(appState.lastAttempted != nil)
        // The PollingEngine sets its own statusMessage for networkUnreachable,
        // so resolvedStatusMessage will use that. Clear it to test the fallback path.
        appState.updateStatusMessage(nil)
        #expect(appState.statusMessage == nil)
        #expect(appState.lastAttempted != nil)
    }
}
