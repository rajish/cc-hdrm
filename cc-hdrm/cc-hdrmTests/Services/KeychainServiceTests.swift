import Foundation
import Testing
@testable import cc_hdrm

@Suite("KeychainService Tests")
struct KeychainServiceTests {

    // MARK: - Valid JSON

    @Test("valid JSON returns correct KeychainCredentials with all fields")
    func validFullJSON() async throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "oauth-token-string",
                "refreshToken": "refresh-token-string",
                "expiresAt": 1738400000000,
                "subscriptionType": "pro",
                "rateLimitTier": "tier_1",
                "scopes": ["user:inference"]
            }
        }
        """.data(using: .utf8)!

        let service = KeychainService(dataProvider: { .success(json) })
        let creds = try await service.readCredentials()

        #expect(creds.accessToken == "oauth-token-string")
        #expect(creds.refreshToken == "refresh-token-string")
        #expect(creds.expiresAt == 1738400000000)
        #expect(creds.subscriptionType == "pro")
        #expect(creds.rateLimitTier == "tier_1")
        #expect(creds.scopes == ["user:inference"])
    }

    // MARK: - Missing Optional Fields

    @Test("valid JSON with missing optional fields returns nils")
    func validMinimalJSON() async throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "token-only"
            }
        }
        """.data(using: .utf8)!

        let service = KeychainService(dataProvider: { .success(json) })
        let creds = try await service.readCredentials()

        #expect(creds.accessToken == "token-only")
        #expect(creds.refreshToken == nil)
        #expect(creds.expiresAt == nil)
        #expect(creds.subscriptionType == nil)
        #expect(creds.rateLimitTier == nil)
        #expect(creds.scopes == nil)
    }

    // MARK: - Malformed JSON

    @Test("malformed JSON throws keychainInvalidFormat")
    func malformedJSON() async {
        let badData = "not json".data(using: .utf8)!
        let service = KeychainService(dataProvider: { .success(badData) })

        await #expect(throws: AppError.keychainInvalidFormat) {
            _ = try await service.readCredentials()
        }
    }

    @Test("JSON missing claudeAiOauth key throws keychainInvalidFormat")
    func missingOauthKey() async {
        let json = """
        { "someOtherKey": {} }
        """.data(using: .utf8)!

        let service = KeychainService(dataProvider: { .success(json) })

        await #expect(throws: AppError.keychainInvalidFormat) {
            _ = try await service.readCredentials()
        }
    }

    // MARK: - No Keychain Item

    @Test("no keychain item throws keychainNotFound")
    func noKeychainItem() async {
        let service = KeychainService(dataProvider: { .notFound })

        await #expect(throws: AppError.keychainNotFound) {
            _ = try await service.readCredentials()
        }
    }

    // MARK: - Access Denied

    @Test("access denied throws keychainAccessDenied")
    func accessDenied() async {
        let service = KeychainService(dataProvider: { .accessDenied })

        await #expect(throws: AppError.keychainAccessDenied) {
            _ = try await service.readCredentials()
        }
    }

    @Test("unknown OSStatus error throws keychainAccessDenied")
    func unknownOSStatusError() async {
        let service = KeychainService(dataProvider: { .error(-25293) })

        await #expect(throws: AppError.keychainAccessDenied) {
            _ = try await service.readCredentials()
        }
    }
}
