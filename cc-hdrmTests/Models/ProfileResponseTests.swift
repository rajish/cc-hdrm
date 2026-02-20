import Foundation
import Testing
@testable import cc_hdrm

@Suite("ProfileResponse Codable Tests")
struct ProfileResponseTests {

    @Test("full profile response parses all fields correctly")
    func fullResponseParsesAllFields() throws {
        let json = """
        {
            "account": {
                "uuid": "acc-uuid",
                "email_address": "user@example.com",
                "display_name": "Test User"
            },
            "organization": {
                "uuid": "org-uuid",
                "organization_type": "claude_max",
                "rate_limit_tier": "default_claude_max_20x",
                "has_extra_usage_enabled": true,
                "billing_type": "stripe",
                "subscription_created_at": "2025-01-01T00:00:00Z"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProfileResponse.self, from: json)

        #expect(response.organization?.rateLimitTier == "default_claude_max_20x")
        #expect(response.organization?.organizationType == "claude_max")
    }

    @Test("response with missing organization parses without crash")
    func missingOrganizationParses() throws {
        let json = """
        {
            "account": {
                "uuid": "acc-uuid",
                "email_address": "user@example.com"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProfileResponse.self, from: json)

        #expect(response.organization == nil)
    }

    @Test("response with missing rate_limit_tier and organization_type parses as nil")
    func missingFieldsParseAsNil() throws {
        let json = """
        {
            "organization": {
                "uuid": "org-uuid"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProfileResponse.self, from: json)

        #expect(response.organization != nil)
        #expect(response.organization?.rateLimitTier == nil)
        #expect(response.organization?.organizationType == nil)
    }

    @Test("empty JSON object parses as all-nil ProfileResponse")
    func emptyObjectParsesAllNil() throws {
        let json = "{}".data(using: .utf8)!

        let response = try JSONDecoder().decode(ProfileResponse.self, from: json)

        #expect(response.organization == nil)
    }

    @Test("unknown organization_type maps subscriptionTypeDisplay to nil")
    func unknownOrganizationTypeMapsToNil() throws {
        let json = """
        {
            "organization": {
                "organization_type": "some_future_plan"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProfileResponse.self, from: json)

        #expect(response.organization?.subscriptionTypeDisplay == nil)
    }

    @Test("malformed JSON throws decode error")
    func malformedJsonThrows() {
        let json = "not json at all".data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ProfileResponse.self, from: json)
        }
    }
}

@Suite("ProfileResponse subscriptionTypeDisplay Mapping Tests")
struct ProfileResponseSubscriptionTypeDisplayTests {

    @Test("claude_pro maps to pro")
    func claudeProMapsToPro() throws {
        let json = """
        { "organization": { "organization_type": "claude_pro" } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProfileResponse.self, from: json)
        #expect(response.organization?.subscriptionTypeDisplay == "pro")
    }

    @Test("claude_max maps to max")
    func claudeMaxMapsToMax() throws {
        let json = """
        { "organization": { "organization_type": "claude_max" } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProfileResponse.self, from: json)
        #expect(response.organization?.subscriptionTypeDisplay == "max")
    }

    @Test("claude_enterprise maps to enterprise")
    func claudeEnterpriseMapsToEnterprise() throws {
        let json = """
        { "organization": { "organization_type": "claude_enterprise" } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProfileResponse.self, from: json)
        #expect(response.organization?.subscriptionTypeDisplay == "enterprise")
    }

    @Test("claude_team maps to team")
    func claudeTeamMapsToTeam() throws {
        let json = """
        { "organization": { "organization_type": "claude_team" } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProfileResponse.self, from: json)
        #expect(response.organization?.subscriptionTypeDisplay == "team")
    }

    @Test("nil organization_type maps to nil")
    func nilOrganizationTypeMapsToNil() throws {
        let json = """
        { "organization": { "uuid": "org-uuid" } }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProfileResponse.self, from: json)
        #expect(response.organization?.subscriptionTypeDisplay == nil)
    }
}
