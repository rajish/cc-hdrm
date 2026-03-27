import Foundation

/// A single token consumption record extracted from a Claude Code JSONL log line.
/// Represents one deduplicated API request with its token breakdown.
struct TokenRecord: Sendable, Equatable, Codable {
    /// Unix milliseconds when the request occurred
    let timestamp: Int64
    /// Model identifier (e.g., "claude-opus-4-6", "claude-sonnet-4-6")
    let model: String
    /// Direct input tokens (excluding cache)
    let inputTokens: Int
    /// Output tokens generated
    let outputTokens: Int
    /// Tokens used to create cache entries
    let cacheCreateTokens: Int
    /// Tokens read from cache
    let cacheReadTokens: Int
}
