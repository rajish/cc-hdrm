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

        let delegate = AppDelegate(
            keychainService: mockKeychain,
            tokenRefreshService: mockRefresh
        )
        delegate.appState = AppState()

        await delegate.performCredentialReadForTesting()

        #expect(delegate.appState?.connectionStatus == .connected)
        #expect(delegate.appState?.statusMessage == nil)
    }
}
