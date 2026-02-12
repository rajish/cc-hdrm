import Foundation

/// Protocol for delivering macOS notifications for detected subscription patterns.
/// Handles cooldown tracking and notification authorization checks.
@MainActor
protocol PatternNotificationServiceProtocol: Sendable {
    /// Processes pattern findings and delivers macOS notifications for actionable ones.
    /// Respects 30-day cooldown per finding type and notification authorization.
    func processFindings(_ findings: [PatternFinding]) async
}
