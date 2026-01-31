import Foundation

/// Abstraction for Keychain credential access.
/// Enables mocking in tests — only `KeychainService` imports Security.
protocol KeychainServiceProtocol: Sendable {
    func readCredentials() async throws -> KeychainCredentials
}
