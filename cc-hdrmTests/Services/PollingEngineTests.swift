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
        return []
    }

    func getLastPoll() async throws -> UsagePoll? {
        return mockLastPoll
    }

    func getResetEvents(fromTimestamp: Int64?, toTimestamp: Int64?) async throws -> [ResetEvent] {
        return mockResetEvents
    }

    func getDatabaseSize() async throws -> Int64 {
        return 0
    }
}

private struct PEMockAPIClient: APIClientProtocol {
    private let resultProvider: ResultProvider
    private let callTracker: APICallTracker

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

    final class APICallTracker: @unchecked Sendable {
        var callCount = 0
        var lastToken: String?
    }

    init(result: UsageResponse? = nil, error: (any Error)? = nil) {
        self.resultProvider = ResultProvider(result: result, error: error)
        self.callTracker = APICallTracker()
    }

    init(results: [Result<UsageResponse, any Error>]) {
        self.resultProvider = ResultProvider(results: results)
        self.callTracker = APICallTracker()
    }

    var fetchCallCount: Int { callTracker.callCount }
    var lastToken: String? { callTracker.lastToken }

    func fetchUsage(token: String) async throws -> UsageResponse {
        callTracker.callCount += 1
        callTracker.lastToken = token
        return try resultProvider.next()
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
        // Verify merged credentials preserve original subscriptionType/rateLimitTier/scopes
        #expect(mockKeychain.writeCallCount == 1, "Refreshed credentials should be written to Keychain")
        #expect(mockKeychain.lastWrittenCredentials?.subscriptionType == "pro", "Merge must preserve original subscriptionType")
        #expect(mockKeychain.lastWrittenCredentials?.rateLimitTier == "tier_1", "Merge must preserve original rateLimitTier")
        #expect(mockKeychain.lastWrittenCredentials?.scopes == ["user:inference"], "Merge must preserve original scopes")
        #expect(mockKeychain.lastWrittenCredentials?.accessToken == "new-token", "Merged credentials should use refreshed accessToken")
    }

    @Test("token expired with no refresh token sets .tokenExpired status")
    @MainActor
    func tokenExpiredNoRefreshToken() async {
        let mockKeychain = PEMockKeychainService(credentials: expiredCredentials(withRefreshToken: false))
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

        #expect(appState.connectionStatus == .tokenExpired)
        #expect(appState.statusMessage == StatusMessage(
            title: "Token expired",
            detail: "Run any Claude Code command to refresh"
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
            title: "No Claude credentials found",
            detail: "Run Claude Code to create them"
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
