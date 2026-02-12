import Foundation

/// Protocol for detecting slow-burn subscription patterns from usage history.
/// Implementations analyze ResetEvent and extra usage data to surface findings
/// that might indicate the user is on the wrong plan or underutilizing their subscription.
protocol SubscriptionPatternDetectorProtocol: Sendable {
    /// Analyzes historical usage data for slow-burn subscription patterns.
    /// Returns an array of detected pattern findings, or an empty array if none are found.
    /// Patterns with insufficient data are silently skipped.
    func analyzePatterns() async throws -> [PatternFinding]
}
