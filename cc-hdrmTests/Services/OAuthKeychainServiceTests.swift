import Foundation
import Testing
@testable import cc_hdrm

@Suite("OAuthKeychainService Tests")
struct OAuthKeychainServiceTests {

    // MARK: - Valid JSON

    @Test("valid JSON returns correct KeychainCredentials with all fields")
    func validFullJSON() async throws {
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

        let service = OAuthKeychainService(dataProvider: { .success(json) })
        let creds = try await service.readCredentials()

        #expect(creds.accessToken == "oauth-token-string")
        #expect(creds.refreshToken == "refresh-token-string")
        #expect(creds.expiresAt == 1738400000000)
        #expect(creds.subscriptionType == "pro")
        #expect(creds.rateLimitTier == "tier_1")
        #expect(creds.scopes == ["user:inference"])
    }

    @Test("valid JSON with only access token returns nils for optional fields")
    func validMinimalJSON() async throws {
        let json = """
        {
            "accessToken": "token-only"
        }
        """.data(using: .utf8)!

        let service = OAuthKeychainService(dataProvider: { .success(json) })
        let creds = try await service.readCredentials()

        #expect(creds.accessToken == "token-only")
        #expect(creds.refreshToken == nil)
        #expect(creds.expiresAt == nil)
    }

    // MARK: - Error Cases

    @Test("malformed JSON throws keychainInvalidFormat")
    func malformedJSON() async {
        let badData = "not json".data(using: .utf8)!
        let service = OAuthKeychainService(dataProvider: { .success(badData) })

        await #expect(throws: AppError.keychainInvalidFormat) {
            _ = try await service.readCredentials()
        }
    }

    @Test("no keychain item throws keychainNotFound")
    func noKeychainItem() async {
        let service = OAuthKeychainService(dataProvider: { .notFound })

        await #expect(throws: AppError.keychainNotFound) {
            _ = try await service.readCredentials()
        }
    }

    @Test("access denied throws keychainAccessDenied")
    func accessDenied() async {
        let service = OAuthKeychainService(dataProvider: { .accessDenied })

        await #expect(throws: AppError.keychainAccessDenied) {
            _ = try await service.readCredentials()
        }
    }

    // MARK: - Write Tests

    final class WriteTracker: @unchecked Sendable {
        var writtenData: Data?
    }

    @Test("writeCredentials stores flat JSON")
    func writeCredentialsStoresFlat() async throws {
        let tracker = WriteTracker()

        let service = OAuthKeychainService(
            dataProvider: { .notFound },
            writeProvider: { data in
                tracker.writtenData = data
                return .success
            }
        )

        let creds = KeychainCredentials(
            accessToken: "new-token",
            refreshToken: "new-refresh",
            expiresAt: 1738400000000,
            subscriptionType: "pro",
            rateLimitTier: "tier_1",
            scopes: nil
        )

        try await service.writeCredentials(creds)
        #expect(tracker.writtenData != nil)

        // Verify written data is flat JSON (not wrapped in claudeAiOauth)
        if let data = tracker.writtenData,
           let parsed = try? JSONDecoder().decode(KeychainCredentials.self, from: data) {
            #expect(parsed.accessToken == "new-token")
            #expect(parsed.refreshToken == "new-refresh")
            #expect(parsed.subscriptionType == "pro")
        } else {
            #expect(Bool(false), "Written data should be decodable as KeychainCredentials")
        }
    }

    @Test("writeCredentials throws on write failure")
    func writeCredentialsWriteFailure() async {
        let service = OAuthKeychainService(
            dataProvider: { .notFound },
            writeProvider: { _ in .error(-25293) }
        )

        let creds = KeychainCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: nil
        )

        await #expect(throws: AppError.keychainAccessDenied) {
            try await service.writeCredentials(creds)
        }
    }
}
