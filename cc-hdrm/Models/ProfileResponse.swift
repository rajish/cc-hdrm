import Foundation

/// Represents the profile data returned by the Claude API `/api/oauth/profile` endpoint.
/// Only `organization.rate_limit_tier` and `organization.organization_type` are used;
/// all other fields are parsed defensively (optional) and ignored.
struct ProfileResponse: Codable, Sendable, Equatable {
    let organization: Organization?

    struct Organization: Codable, Sendable, Equatable {
        let organizationType: String?
        let rateLimitTier: String?

        enum CodingKeys: String, CodingKey {
            case organizationType = "organization_type"
            case rateLimitTier = "rate_limit_tier"
        }

        /// Maps `organization_type` API values to display-friendly subscription names.
        var subscriptionTypeDisplay: String? {
            switch organizationType {
            case "claude_pro": return "pro"
            case "claude_max": return "max"
            case "claude_enterprise": return "enterprise"
            case "claude_team": return "team"
            default: return nil
            }
        }
    }
}
