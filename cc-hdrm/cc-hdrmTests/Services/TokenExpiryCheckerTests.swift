import Foundation
import Testing
@testable import cc_hdrm

@Suite("TokenExpiryChecker Tests")
struct TokenExpiryCheckerTests {

    private let now = Date(timeIntervalSince1970: 1700000000) // Fixed reference time

    // MARK: - Valid Token

    @Test("future expiresAt beyond 5 minutes returns .valid")
    func futureExpiresAtValid() {
        let expiresAtMs = (now.timeIntervalSince1970 + 600) * 1000 // 10 min in future
        let creds = KeychainCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: expiresAtMs,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )

        let status = TokenExpiryChecker.tokenStatus(for: creds, now: now)
        #expect(status == .valid)
    }

    // MARK: - Expiring Soon

    @Test("expiresAt within 5 minutes returns .expiringSoon")
    func expiringSoon() {
        let expiresAtMs = (now.timeIntervalSince1970 + 200) * 1000 // 3 min 20 sec in future
        let creds = KeychainCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: expiresAtMs,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )

        let status = TokenExpiryChecker.tokenStatus(for: creds, now: now)
        #expect(status == .expiringSoon)
    }

    @Test("expiresAt exactly 5 minutes in future returns .expiringSoon")
    func exactlyFiveMinutes() {
        let expiresAtMs = (now.timeIntervalSince1970 + 300) * 1000 // exactly 5 min
        let creds = KeychainCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: expiresAtMs,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )

        let status = TokenExpiryChecker.tokenStatus(for: creds, now: now)
        #expect(status == .expiringSoon)
    }

    // MARK: - Expired

    @Test("past expiresAt returns .expired")
    func pastExpiresAt() {
        let expiresAtMs = (now.timeIntervalSince1970 - 100) * 1000 // 100 sec ago
        let creds = KeychainCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: expiresAtMs,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )

        let status = TokenExpiryChecker.tokenStatus(for: creds, now: now)
        #expect(status == .expired)
    }

    @Test("expiresAt at epoch (0) returns .expired")
    func epochExpiresAt() {
        let creds = KeychainCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: 0,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )

        let status = TokenExpiryChecker.tokenStatus(for: creds, now: now)
        #expect(status == .expired)
    }

    // MARK: - Nil expiresAt

    @Test("nil expiresAt returns .valid")
    func nilExpiresAt() {
        let creds = KeychainCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )

        let status = TokenExpiryChecker.tokenStatus(for: creds, now: now)
        #expect(status == .valid)
    }

    // MARK: - Unix Milliseconds Precision

    @Test("expiresAt at Unix milliseconds precision (large number) works correctly")
    func largeUnixMilliseconds() {
        // Real-world value: Jan 2025 in milliseconds
        let expiresAtMs: Double = 1738400000000
        let expiresAtDate = Date(timeIntervalSince1970: expiresAtMs / 1000.0)
        let beforeExpiry = expiresAtDate.addingTimeInterval(-600) // 10 min before

        let creds = KeychainCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: expiresAtMs,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )

        let status = TokenExpiryChecker.tokenStatus(for: creds, now: beforeExpiry)
        #expect(status == .valid)
    }
}
