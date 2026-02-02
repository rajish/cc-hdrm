import Foundation
import Testing
@testable import cc_hdrm

@Suite("KeychainCredentials Tests")
struct KeychainCredentialsTests {

    // MARK: - Full JSON Decoding

    @Test("decodes full JSON payload with all fields")
    func decodesFullPayload() throws {
        let json = """
        {
            "accessToken": "oauth-token-string",
            "refreshToken": "refresh-token-string",
            "expiresAt": 1738400000000,
            "subscriptionType": "pro",
            "rateLimitTier": "tier_1",
            "scopes": ["user:inference"]
        }
        """.data(using: .utf8)!

        let creds = try JSONDecoder().decode(KeychainCredentials.self, from: json)
        #expect(creds.accessToken == "oauth-token-string")
        #expect(creds.refreshToken == "refresh-token-string")
        #expect(creds.expiresAt == 1738400000000)
        #expect(creds.subscriptionType == "pro")
        #expect(creds.rateLimitTier == "tier_1")
        #expect(creds.scopes == ["user:inference"])
    }

    // MARK: - Missing Optional Fields

    @Test("decodes JSON with only accessToken (all optionals missing)")
    func decodesMinimalPayload() throws {
        let json = """
        { "accessToken": "token-only" }
        """.data(using: .utf8)!

        let creds = try JSONDecoder().decode(KeychainCredentials.self, from: json)
        #expect(creds.accessToken == "token-only")
        #expect(creds.refreshToken == nil)
        #expect(creds.expiresAt == nil)
        #expect(creds.subscriptionType == nil)
        #expect(creds.rateLimitTier == nil)
        #expect(creds.scopes == nil)
    }

    // MARK: - expiresAt handles large Unix ms values

    @Test("expiresAt handles large Unix millisecond timestamps")
    func expiresAtHandlesLargeNumbers() throws {
        let json = """
        { "accessToken": "t", "expiresAt": 1738400000000 }
        """.data(using: .utf8)!

        let creds = try JSONDecoder().decode(KeychainCredentials.self, from: json)
        #expect(creds.expiresAt == 1738400000000)
    }

    // MARK: - Codable Round-Trip

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = KeychainCredentials(
            accessToken: "at",
            refreshToken: "rt",
            expiresAt: 1738400000000,
            subscriptionType: "max",
            rateLimitTier: "tier_2",
            scopes: ["user:inference", "admin"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeychainCredentials.self, from: data)

        #expect(decoded.accessToken == original.accessToken)
        #expect(decoded.refreshToken == original.refreshToken)
        #expect(decoded.expiresAt == original.expiresAt)
        #expect(decoded.subscriptionType == original.subscriptionType)
        #expect(decoded.rateLimitTier == original.rateLimitTier)
        #expect(decoded.scopes == original.scopes)
    }

    // MARK: - Sendable Conformance

    @Test("KeychainCredentials is Sendable")
    func sendableConformance() {
        let creds = KeychainCredentials(
            accessToken: "t",
            refreshToken: nil,
            expiresAt: nil,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )
        // Sendable check: pass across isolation boundary
        let _: any Sendable = creds
    }

    // MARK: - Missing accessToken fails decoding

    @Test("missing accessToken throws decoding error")
    func missingAccessTokenFails() {
        let json = """
        { "refreshToken": "rt" }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(KeychainCredentials.self, from: json)
        }
    }

    // MARK: - Security: No CustomStringConvertible

    @Test("KeychainCredentials does NOT conform to CustomStringConvertible")
    func noCustomStringConvertible() {
        let creds = KeychainCredentials(
            accessToken: "secret-token",
            refreshToken: "secret-refresh",
            expiresAt: nil,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )
        // If KeychainCredentials conformed to CustomStringConvertible,
        // String(describing:) would use that implementation.
        // Since it doesn't, it uses the default struct description.
        // We verify the type does NOT conform.
        #expect(!(creds is any CustomStringConvertible))
        #expect(!(creds is any CustomDebugStringConvertible))
    }

    // MARK: - Realistic Claude Code JSON payload

    @Test("decodes realistic Claude Code stored JSON format")
    func decodesRealisticPayload() throws {
        // Simulates the exact JSON structure Claude Code stores in Keychain
        let json = """
        {
            "accessToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.example",
            "refreshToken": "dGhpcyBpcyBhIHJlZnJlc2ggdG9rZW4",
            "expiresAt": 1738400000000,
            "subscriptionType": "pro",
            "rateLimitTier": "tier_1",
            "scopes": ["user:inference"]
        }
        """.data(using: .utf8)!

        let creds = try JSONDecoder().decode(KeychainCredentials.self, from: json)
        #expect(creds.accessToken.starts(with: "eyJ"))
        #expect(creds.expiresAt == 1738400000000)
        // Verify Unix ms → Date conversion works correctly
        let expiresDate = Date(timeIntervalSince1970: creds.expiresAt! / 1000)
        #expect(expiresDate > Date(timeIntervalSince1970: 0))
    }
}
