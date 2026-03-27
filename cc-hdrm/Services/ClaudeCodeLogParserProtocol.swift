import Foundation

/// Protocol for the Claude Code log parser service, enabling testability via dependency injection.
/// Implementations scan Claude Code JSONL session logs and extract token consumption data.
protocol ClaudeCodeLogParserProtocol: Sendable {
    /// Perform a full or incremental scan of Claude Code session logs.
    /// Discovers JSONL files, reads new data since last scan, and updates in-memory token records.
    func scan() async

    /// Get aggregated token consumption for a time range, optionally filtered by model.
    /// - Parameters:
    ///   - start: Start of time range (Unix milliseconds, inclusive)
    ///   - end: End of time range (Unix milliseconds, exclusive)
    ///   - model: Optional model filter (e.g., "claude-opus-4-6"). Nil returns all models.
    /// - Returns: Per-model token aggregates with raw counts only (no weighted blending)
    func getTokens(from start: Int64, to end: Int64, model: String?) -> [TokenAggregate]

    /// Get current health status of the parser.
    /// - Returns: Health metrics including success rate, line counts, and scan timestamps
    func getHealth() -> LogParserHealth
}

// MARK: - Default convenience overload

extension ClaudeCodeLogParserProtocol {
    /// Convenience overload without model filter.
    func getTokens(from start: Int64, to end: Int64) -> [TokenAggregate] {
        getTokens(from: start, to: end, model: nil)
    }
}
