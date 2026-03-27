/// Protocol for the background polling engine that fetches usage data on a schedule.
@MainActor
protocol PollingEngineProtocol: Sendable {
    /// Starts the polling loop. Performs an initial fetch immediately, then polls every 30 seconds.
    func start() async
    /// Stops the polling loop by cancelling the internal task.
    func stop()
    /// Restarts the polling loop with the current poll interval.
    /// Cancels the in-flight sleep and starts a new loop WITHOUT an immediate poll cycle.
    func restartPolling()
    /// Performs a single forced poll cycle immediately, bypassing the sleep loop.
    /// Used by BenchmarkService to get updated utilization after sending a test request.
    func performForcedPoll() async
}
