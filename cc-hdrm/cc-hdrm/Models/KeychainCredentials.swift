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
}
