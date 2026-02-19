import AppKit
import CryptoKit
import Foundation
import os

/// Orchestrates the full OAuth authorization flow with PKCE:
/// starts callback server → opens browser → awaits callback → exchanges code for tokens.
final class OAuthService: OAuthServiceProtocol, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "oauth"
    )

    private static let authorizeEndpoint = URL(string: "https://claude.ai/oauth/authorize")!
    private static let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let scope = "org:create_api_key user:profile user:inference"

    /// Abstraction for network requests — enables test injection.
    private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Abstraction for opening URLs — enables test injection.
    private let urlOpener: @Sendable (URL) -> Bool

    /// Production initializer.
    init() {
        self.dataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
        self.urlOpener = { url in
            NSWorkspace.shared.open(url)
        }
    }

    /// Test initializer — injects network layer and URL opener.
    init(
        dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
        urlOpener: @escaping @Sendable (URL) -> Bool = { _ in true }
    ) {
        self.dataLoader = dataLoader
        self.urlOpener = urlOpener
    }

    func authorize() async throws -> KeychainCredentials {
        // Generate PKCE parameters
        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.generateCodeChallenge(from: codeVerifier)
        let state = Self.generateState()

        Self.logger.info("PKCE parameters generated")

        // Start callback server — awaits until listener is bound and port is known
        let server = OAuthCallbackServer(expectedState: state)

        return try await withTaskCancellationHandler {
            let actualPort = try await server.start()

            let redirectUri = "http://localhost:\(actualPort)/callback"

            // Build authorization URL
            let authURL = Self.buildAuthorizationURL(
                codeChallenge: codeChallenge,
                state: state,
                redirectUri: redirectUri
            )

            // Open browser
            let opened = urlOpener(authURL)
            if opened {
                Self.logger.info("Browser opened for OAuth authorization")
            } else {
                Self.logger.error("Failed to open browser for OAuth authorization — URL: \(authURL.absoluteString)")
                server.stop()
                throw AppError.oauthAuthorizationFailed("Could not open browser. Visit: \(authURL.absoluteString)")
            }

            // Wait for callback (blocks until redirect or 5-minute timeout)
            let callbackResult: OAuthCallbackResult
            do {
                callbackResult = try await server.waitForCallback()
            } catch {
                server.stop()
                throw error
            }

            Self.logger.info("Authorization code received, exchanging for tokens")

            // Exchange code for tokens
            let credentials = try await exchangeCode(
                code: callbackResult.code,
                state: callbackResult.state,
                codeVerifier: codeVerifier,
                redirectUri: redirectUri
            )

            Self.logger.info("Token exchange succeeded")
            return credentials
        } onCancel: {
            server.stop()
        }
    }

    // MARK: - PKCE Generation

    /// Generates a code verifier: 32 random bytes, base64url-encoded (43 chars).
    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return Data(bytes).base64URLEncodedString()
    }

    /// Generates the code challenge: SHA256 of the verifier, base64url-encoded.
    static func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    /// Generates a random state parameter: 32 random bytes, hex-encoded.
    static func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - URL Building

    static func buildAuthorizationURL(
        codeChallenge: String,
        state: String,
        redirectUri: String
    ) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }

    // MARK: - Token Exchange

    func exchangeCode(
        code: String,
        state: String,
        codeVerifier: String,
        redirectUri: String
    ) async throws -> KeychainCredentials {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "code": code,
            "state": state,
            "grant_type": "authorization_code",
            "client_id": Self.clientId,
            "redirect_uri": redirectUri,
            "code_verifier": codeVerifier
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataLoader(request)
        } catch {
            Self.logger.error("Token exchange network request failed: \(error.localizedDescription)")
            throw AppError.oauthTokenExchangeFailed(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Token exchange received non-HTTP response")
            throw AppError.oauthTokenExchangeFailed(underlying: URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            Self.logger.error("Token exchange failed with status \(httpResponse.statusCode): \(bodyString)")
            throw AppError.oauthTokenExchangeFailed(underlying: URLError(.badServerResponse))
        }

        let parsed: [String: Any]
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Self.logger.error("Token exchange response is not a JSON object")
                throw AppError.oauthTokenExchangeFailed(underlying: URLError(.cannotParseResponse))
            }
            parsed = json
        } catch let error as AppError {
            throw error
        } catch {
            Self.logger.error("Token exchange response parse failed: \(error.localizedDescription)")
            throw AppError.oauthTokenExchangeFailed(underlying: URLError(.cannotParseResponse))
        }

        guard let accessToken = parsed["access_token"] as? String else {
            Self.logger.error("Token exchange response missing access_token")
            throw AppError.oauthTokenExchangeFailed(underlying: URLError(.cannotParseResponse))
        }

        let refreshToken = parsed["refresh_token"] as? String

        // Convert expires_in (seconds) to expiresAt (Unix milliseconds)
        let expiresAt: Double?
        if let expiresIn = parsed["expires_in"] as? Double {
            expiresAt = (Date().timeIntervalSince1970 + expiresIn) * 1000
        } else {
            expiresAt = nil
        }

        // Handle scope as either [String] array or space-separated string (RFC 6749 Section 5.1)
        let scopes: [String]?
        if let scopeArray = parsed["scope"] as? [String] {
            scopes = scopeArray
        } else if let scopeString = parsed["scope"] as? String {
            scopes = scopeString.split(separator: " ").map(String.init)
        } else {
            scopes = nil
        }

        return KeychainCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            subscriptionType: nil,
            rateLimitTier: nil,
            scopes: scopes
        )
    }
}

// MARK: - Base64URL Encoding

extension Data {
    /// Base64url encoding without padding, per RFC 4648 Section 5.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
