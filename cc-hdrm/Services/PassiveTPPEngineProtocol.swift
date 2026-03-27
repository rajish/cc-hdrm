import Foundation

/// Protocol for the passive TPP measurement engine, enabling testability via dependency injection.
/// Implementations correlate token consumption from Claude Code logs with utilization changes
/// to compute tokens-per-percent measurements passively between polls.
protocol PassiveTPPEngineProtocol: Sendable {
    /// Processes a pair of consecutive polls to detect utilization changes and correlate tokens.
    /// - Parameters:
    ///   - current: The most recent poll data
    ///   - previous: The preceding poll data
    func processPoll(current: UsagePoll, previous: UsagePoll) async

    /// Returns health metrics for the passive measurement engine.
    func getHealth() async -> PassiveTPPHealth

    /// Discards any in-progress accumulation window and resets to a clean state.
    func resetAccumulation() async
}
