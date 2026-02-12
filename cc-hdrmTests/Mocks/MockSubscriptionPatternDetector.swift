import Foundation
@testable import cc_hdrm

/// Mock for SubscriptionPatternDetector used across test suites.
final class MockSubscriptionPatternDetector: SubscriptionPatternDetectorProtocol, @unchecked Sendable {
    var findingsToReturn: [PatternFinding] = []
    var analyzeCallCount = 0
    var shouldThrow = false

    func analyzePatterns() async throws -> [PatternFinding] {
        analyzeCallCount += 1
        if shouldThrow {
            throw AppError.databaseQueryFailed(underlying: NSError(domain: "test", code: 1))
        }
        return findingsToReturn
    }
}
