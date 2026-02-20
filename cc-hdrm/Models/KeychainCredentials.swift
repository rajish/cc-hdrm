import Foundation

/// OAuth credentials read from macOS Keychain (claudeAiOauth object).
/// Lives only in memory — never persisted to disk, logs, or UserDefaults.
struct KeychainCredentials: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Double?
    let subscriptionType: String?
    let rateLimitTier: String?
    let scopes: [String]?

    /// Returns a copy with `rateLimitTier` and `subscriptionType` merged from a profile response.
    /// Profile values take precedence; falls back to existing values when profile fields are nil.
    func applying(_ profile: ProfileResponse) -> KeychainCredentials {
        KeychainCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            subscriptionType: profile.organization?.subscriptionTypeDisplay ?? subscriptionType,
            rateLimitTier: profile.organization?.rateLimitTier ?? rateLimitTier,
            scopes: scopes
        )
    }
}
