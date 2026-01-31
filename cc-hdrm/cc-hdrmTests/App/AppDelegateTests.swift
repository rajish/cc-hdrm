import Foundation
import Testing
@testable import cc_hdrm

// MARK: - Mock Services

struct MockKeychainService: KeychainServiceProtocol {
    let credentials: KeychainCredentials?
    let readError: (any Error)?

    // Use a class wrapper to capture writes since structs are value types
    private let writeTracker: WriteTracker

    final class WriteTracker: @unchecked Sendable {
        var writtenCredentials: KeychainCredentials?
        var writeError: (any Error)?
    }

    init(
        credentials: KeychainCredentials? = nil,
        readError: (any Error)? = nil,
        writeError: (any Error)? = nil
    ) {
        self.credentials = credentials
        self.readError = readError
        let tracker = WriteTracker()
        tracker.writeError = writeError
        self.writeTracker = tracker
    }

    func readCredentials() async throws -> KeychainCredentials {
        if let error = readError {
            throw error
        }
        guard let credentials else {
            throw AppError.keychainNotFound
        }
        return credentials
    }

    func writeCredentials(_ credentials: KeychainCredentials) async throws {
        if let error = writeTracker.writeError {
            throw error
        }
        writeTracker.writtenCredentials = credentials
    }

    var lastWrittenCredentials: KeychainCredentials? {
        writeTracker.writtenCredentials
    }
}

struct MockTokenRefreshService: TokenRefreshServiceProtocol {
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

// MARK: - Mock API Client

struct MockAPIClient: APIClientProtocol {
    let result: UsageResponse?
    let error: (any Error)?
    private let callTracker: APICallTracker

    final class APICallTracker: @unchecked Sendable {
        var callCount = 0
        var lastToken: String?
    }

    init(result: UsageResponse? = nil, error: (any Error)? = nil) {
        self.result = result
        self.error = error
        self.callTracker = APICallTracker()
    }

    var fetchCallCount: Int { callTracker.callCount }
    var lastToken: String? { callTracker.lastToken }

    func fetchUsage(token: String) async throws -> UsageResponse {
        callTracker.callCount += 1
        callTracker.lastToken = token
        if let error {
            throw error
        }
        guard let result else {
            throw AppError.apiError(statusCode: 500, body: "mock not configured")
        }
        return result
    }
}

// MARK: - AppDelegate Integration Tests

@Suite("AppDelegate Token Refresh Integration Tests")
struct AppDelegateTests {

    @Test("expired token with successful refresh sets connected status")
    @MainActor
    func expiredTokenRefreshSuccess() async {
        let expiredCreds = KeychainCredentials(
            accessToken: "old-token",
            refreshToken: "refresh-token",
            expiresAt: 1000, // epoch — clearly expired
            subscriptionType: "pro",
            rateLimitTier: "tier_1",
            scopes: ["user:inference"]
        )

        let refreshedCreds = KeychainCredentials(
            accessToken: "new-token",
            refreshToken: "new-refresh",
            expiresAt: (Date().timeIntervalSince1970 + 3600) * 1000,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )

        let mockKeychain = MockKeychainService(credentials: expiredCreds)
        let mockRefresh = MockTokenRefreshService(result: refreshedCreds)

        let delegate = AppDelegate(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh
        )
        delegate.appState = AppState()

        // Trigger the credential read which should detect expiry and refresh
        await delegate.performCredentialReadForTesting()

        #expect(delegate.appState?.connectionStatus == .connected)
        #expect(delegate.appState?.statusMessage == nil)
    }

    @Test("expired token with failed refresh sets tokenExpired status")
    @MainActor
    func expiredTokenRefreshFailure() async {
        let expiredCreds = KeychainCredentials(
            accessToken: "old-token",
            refreshToken: "refresh-token",
            expiresAt: 1000, // expired
            subscriptionType: "pro",
            rateLimitTier: nil,
            scopes: nil
        )

        let mockKeychain = MockKeychainService(credentials: expiredCreds)
        let mockRefresh = MockTokenRefreshService(
            error: AppError.tokenRefreshFailed(underlying: URLError(.badServerResponse))
        )

        let delegate = AppDelegate(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh
        )
        delegate.appState = AppState()

        await delegate.performCredentialReadForTesting()

        #expect(delegate.appState?.connectionStatus == .tokenExpired)
        #expect(delegate.appState?.statusMessage == StatusMessage(
            title: "Token expired",
            detail: "Run any Claude Code command to refresh"
        ))
    }

    @Test("expired token with nil refreshToken sets tokenExpired without attempting refresh")
    @MainActor
    func expiredTokenNoRefreshToken() async {
        let expiredCreds = KeychainCredentials(
            accessToken: "old-token",
            refreshToken: nil, // no refresh token available
            expiresAt: 1000,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )

        let mockKeychain = MockKeychainService(credentials: expiredCreds)
        // This should never be called — tracked via callCount
        let mockRefresh = MockTokenRefreshService(result: KeychainCredentials(
            accessToken: "should-not-happen",
            refreshToken: nil,
            expiresAt: nil,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        ))

        let delegate = AppDelegate(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh
        )
        delegate.appState = AppState()

        await delegate.performCredentialReadForTesting()

        #expect(delegate.appState?.connectionStatus == .tokenExpired)
        #expect(delegate.appState?.statusMessage == StatusMessage(
            title: "Token expired",
            detail: "Run any Claude Code command to refresh"
        ))
        #expect(mockRefresh.refreshCallCount == 0, "Refresh service should not be called when refreshToken is nil")
    }

    @Test("valid token sets connected status without refresh")
    @MainActor
    func validTokenNoRefresh() async {
        let validCreds = KeychainCredentials(
            accessToken: "valid-token",
            refreshToken: "refresh-token",
            expiresAt: (Date().timeIntervalSince1970 + 7200) * 1000, // 2 hours from now
            subscriptionType: "pro",
            rateLimitTier: nil,
            scopes: nil
        )

        let mockKeychain = MockKeychainService(credentials: validCreds)
        let mockRefresh = MockTokenRefreshService(
            error: AppError.tokenRefreshFailed(underlying: URLError(.badServerResponse))
        )
        let mockAPI = MockAPIClient(result: UsageResponse(
            fiveHour: WindowUsage(utilization: 18.0, resetsAt: nil),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        ))

        let delegate = AppDelegate(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI
        )
        delegate.appState = AppState()

        await delegate.performCredentialReadForTesting()

        #expect(delegate.appState?.connectionStatus == .connected)
        #expect(delegate.appState?.statusMessage == nil)
    }
}

// MARK: - AppDelegate API Fetch Integration Tests

@Suite("AppDelegate API Fetch Integration Tests")
struct AppDelegateAPITests {

    private static func validCredentials() -> KeychainCredentials {
        KeychainCredentials(
            accessToken: "valid-token",
            refreshToken: "refresh-token",
            expiresAt: (Date().timeIntervalSince1970 + 7200) * 1000,
            subscriptionType: "pro",
            rateLimitTier: nil,
            scopes: nil
        )
    }

    @Test("valid credentials + successful fetch populates fiveHour and sets connected")
    @MainActor
    func successfulFetchPopulatesState() async {
        let mockKeychain = MockKeychainService(credentials: Self.validCredentials())
        let mockRefresh = MockTokenRefreshService()
        let mockAPI = MockAPIClient(result: UsageResponse(
            fiveHour: WindowUsage(utilization: 18.0, resetsAt: "2026-01-31T01:59:59.782798+00:00"),
            sevenDay: WindowUsage(utilization: 6.0, resetsAt: "2026-02-06T08:59:59+00:00"),
            sevenDaySonnet: nil,
            extraUsage: nil
        ))

        let delegate = AppDelegate(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI
        )
        delegate.appState = AppState()

        await delegate.performCredentialReadForTesting()

        #expect(delegate.appState?.fiveHour?.utilization == 18.0)
        #expect(delegate.appState?.sevenDay?.utilization == 6.0)
        #expect(delegate.appState?.connectionStatus == .connected)
        #expect(delegate.appState?.statusMessage == nil)
    }

    @Test("valid credentials + 401 triggers token refresh")
    @MainActor
    func apiError401TriggersRefresh() async {
        let mockKeychain = MockKeychainService(credentials: Self.validCredentials())
        let mockRefresh = MockTokenRefreshService(result: KeychainCredentials(
            accessToken: "new-token",
            refreshToken: "new-refresh",
            expiresAt: (Date().timeIntervalSince1970 + 3600) * 1000,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        ))
        let mockAPI = MockAPIClient(error: AppError.apiError(statusCode: 401, body: "Unauthorized"))

        let delegate = AppDelegate(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI
        )
        delegate.appState = AppState()

        await delegate.performCredentialReadForTesting()

        #expect(mockRefresh.refreshCallCount == 1, "Token refresh should be triggered on 401")
    }

    @Test("valid credentials + network error sets disconnected")
    @MainActor
    func networkErrorSetsDisconnected() async {
        let mockKeychain = MockKeychainService(credentials: Self.validCredentials())
        let mockRefresh = MockTokenRefreshService()
        let mockAPI = MockAPIClient(error: AppError.networkUnreachable)

        let delegate = AppDelegate(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI
        )
        delegate.appState = AppState()

        await delegate.performCredentialReadForTesting()

        #expect(delegate.appState?.connectionStatus == .disconnected)
        #expect(delegate.appState?.statusMessage?.title == "Unable to reach Claude API")
    }

    @Test("valid credentials + parse error sets disconnected with format message")
    @MainActor
    func parseErrorSetsDisconnected() async {
        let mockKeychain = MockKeychainService(credentials: Self.validCredentials())
        let mockRefresh = MockTokenRefreshService()
        let mockAPI = MockAPIClient(error: AppError.parseError(underlying: URLError(.cannotDecodeContentData)))

        let delegate = AppDelegate(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh,
            apiClient: mockAPI
        )
        delegate.appState = AppState()

        await delegate.performCredentialReadForTesting()

        #expect(delegate.appState?.connectionStatus == .disconnected)
        #expect(delegate.appState?.statusMessage?.title == "Unexpected API response format")
    }
}
