import Foundation

/// Abstraction for OAuth token refresh operations.
/// Enables mocking in tests — only `TokenRefreshService` makes network calls.
protocol TokenRefreshServiceProtocol: Sendable {
    func refreshToken(using refreshToken: String) async throws -> KeychainCredentials
}
