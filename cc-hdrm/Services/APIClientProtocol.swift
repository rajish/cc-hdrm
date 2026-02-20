import Foundation

/// Protocol for fetching usage data from the Claude API.
protocol APIClientProtocol: Sendable {
    /// Fetches current usage data using the provided OAuth token.
    /// - Parameter token: A valid OAuth access token.
    /// - Returns: The parsed usage response.
    /// - Throws: `AppError.apiError`, `AppError.networkUnreachable`, or `AppError.parseError`.
    func fetchUsage(token: String) async throws -> UsageResponse

    /// Fetches profile data (organization type, rate limit tier) using the provided OAuth token.
    /// - Parameter token: A valid OAuth access token.
    /// - Returns: The parsed profile response.
    /// - Throws: `AppError.apiError`, `AppError.networkUnreachable`, or `AppError.parseError`.
    func fetchProfile(token: String) async throws -> ProfileResponse
}
