import Foundation
import os

/// Fetches usage data from the Claude API. Uses injectable dataLoader for testability.
struct APIClient: APIClientProtocol, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "api"
    )

    private static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

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
        Self.logger.info("Fetching usage data")

        var request = URLRequest(url: Self.usageEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/1.0", forHTTPHeaderField: "User-Agent")
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

        Self.logger.info("Usage API responded with status \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            throw AppError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        do {
            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            Self.logger.info("Usage data parsed successfully")
            return decoded
        } catch {
            Self.logger.error("Failed to decode usage response: \(error.localizedDescription)")
            throw AppError.parseError(underlying: error)
        }
    }
}
