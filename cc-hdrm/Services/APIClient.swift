import Foundation
import os

/// Fetches usage data from the Claude API. Uses injectable dataLoader for testability.
struct APIClient: APIClientProtocol, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "api"
    )

    private static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    /// User-Agent header: cc-hdrm/{version} read from Info.plist, fallback to "cc-hdrm/unknown".
    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return "cc-hdrm/\(version)"
    }()

    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let dataLoader: DataLoader

    /// Production initializer — uses URLSession.shared.
    init() {
        self.dataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    }

    /// Test initializer — injects network layer.
    init(dataLoader: @escaping DataLoader) {
        self.dataLoader = dataLoader
    }

    func fetchUsage(token: String) async throws -> UsageResponse {
        try await fetch(endpoint: Self.usageEndpoint, label: "Usage", token: token)
    }

    func fetchProfile(token: String) async throws -> ProfileResponse {
        try await fetch(endpoint: Self.profileEndpoint, label: "Profile", token: token)
    }

    // MARK: - Private

    private func fetch<T: Decodable>(endpoint: URL, label: String, token: String) async throws -> T {
        Self.logger.info("Fetching \(label, privacy: .public) data")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataLoader(request)
        } catch let error as URLError {
            Self.logger.error("Network request failed: \(error.localizedDescription)")
            throw AppError.networkUnreachable
        } catch {
            Self.logger.error("Network request failed with unexpected error: \(error.localizedDescription)")
            throw AppError.networkUnreachable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Received non-HTTP response")
            throw AppError.networkUnreachable
        }

        Self.logger.info("\(label, privacy: .public) API responded with status \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            throw AppError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            Self.logger.info("\(label, privacy: .public) data parsed successfully")
            return decoded
        } catch {
            Self.logger.error("Failed to decode \(label, privacy: .public) response: \(error.localizedDescription)")
            throw AppError.parseError(underlying: error)
        }
    }
}
