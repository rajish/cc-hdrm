import Foundation
import os

/// Refreshes Claude Code OAuth tokens via the platform API.
/// NEVER logs token values. Uses async/await exclusively.
final class TokenRefreshService: TokenRefreshServiceProtocol, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "token"
    )

    private static let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    
    /// Anthropic's public OAuth client ID (used by Claude Code and OpenCode)
    private static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// Abstraction for network requests — enables test injection.
    private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Production initializer — uses URLSession.shared.
    init() {
        self.dataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    }

    /// Test initializer — injects network layer.
    init(dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.dataLoader = dataLoader
    }

    func refreshToken(using refreshToken: String) async throws -> KeychainCredentials {
        Self.logger.info("Attempting token refresh")

        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        guard let encodedToken = refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            Self.logger.error("Failed to URL-encode refresh token")
            throw AppError.tokenRefreshFailed(underlying: URLError(.badURL))
        }
        let body = "grant_type=refresh_token&refresh_token=\(encodedToken)&client_id=\(Self.clientId)"
        request.httpBody = body.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataLoader(request)
        } catch {
            Self.logger.error("Token refresh network request failed: \(error.localizedDescription)")
            throw AppError.tokenRefreshFailed(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Token refresh received non-HTTP response")
            throw AppError.tokenRefreshFailed(
                underlying: URLError(.badServerResponse)
            )
        }

        guard httpResponse.statusCode == 200 else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            Self.logger.error("Token refresh failed with status \(httpResponse.statusCode): \(bodyString)")
            throw AppError.tokenRefreshFailed(
                underlying: URLError(.badServerResponse)
            )
        }

        // Parse OAuth2 token response
        let parsed: [String: Any]
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Self.logger.error("Token refresh response is not a JSON object")
                throw AppError.tokenRefreshFailed(underlying: URLError(.cannotParseResponse))
            }
            parsed = json
        } catch let error as AppError {
            throw error
        } catch {
            Self.logger.error("Token refresh response parse failed: \(error.localizedDescription)")
            throw AppError.tokenRefreshFailed(underlying: URLError(.cannotParseResponse))
        }

        guard let newAccessToken = parsed["access_token"] as? String else {
            Self.logger.error("Token refresh response missing access_token")
            throw AppError.tokenRefreshFailed(underlying: URLError(.cannotParseResponse))
        }

        // New refresh token is optional — keep old if not returned
        let newRefreshToken = parsed["refresh_token"] as? String ?? refreshToken

        // Convert expires_in (seconds) to expiresAt (Unix milliseconds)
        let expiresAt: Double?
        if let expiresIn = parsed["expires_in"] as? Double {
            expiresAt = (Date().timeIntervalSince1970 + expiresIn) * 1000
        } else {
            expiresAt = nil
        }

        Self.logger.info("Token refresh succeeded")

        return KeychainCredentials(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
            expiresAt: expiresAt,
            subscriptionType: nil,  // Caller preserves original values
            rateLimitTier: nil,
            scopes: nil
        )
    }
}
