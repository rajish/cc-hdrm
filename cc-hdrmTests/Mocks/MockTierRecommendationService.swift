import Foundation
@testable import cc_hdrm

/// Shared mock for TierRecommendationServiceProtocol used across test suites.
final class MockTierRecommendationService: TierRecommendationServiceProtocol, @unchecked Sendable {
    var recommendTierCallCount = 0
    var lastQueriedRange: TimeRange?
    var mockRecommendation: TierRecommendation?
    var shouldThrow = false

    func recommendTier(for range: TimeRange) async throws -> TierRecommendation? {
        recommendTierCallCount += 1
        lastQueriedRange = range
        if shouldThrow {
            throw AppError.databaseQueryFailed(underlying: NSError(domain: "test", code: 1))
        }
        return mockRecommendation
    }
}
