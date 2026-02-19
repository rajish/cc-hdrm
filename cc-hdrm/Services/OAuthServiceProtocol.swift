import Foundation

/// Abstraction for the OAuth authorization flow.
/// Enables mocking in tests — only `OAuthService` depends on browser + network.
protocol OAuthServiceProtocol: Sendable {
    func authorize() async throws -> KeychainCredentials
}
