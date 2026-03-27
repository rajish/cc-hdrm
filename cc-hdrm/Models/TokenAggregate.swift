import Foundation

/// Per-model aggregation of token consumption over a time range.
/// Contains raw token counts only — no weighted blending is applied.
struct TokenAggregate: Sendable, Equatable {
    /// Model identifier (e.g., "claude-opus-4-6")
    let model: String
    /// Total direct input tokens (excluding cache)
    var inputTokens: Int
    /// Total output tokens
    var outputTokens: Int
    /// Total cache creation tokens
    var cacheCreateTokens: Int
    /// Total cache read tokens
    var cacheReadTokens: Int
    /// Number of API requests in this aggregate
    var messageCount: Int
}
