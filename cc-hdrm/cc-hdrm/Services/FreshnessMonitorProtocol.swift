/// Protocol for the freshness monitor that periodically checks data staleness.
@MainActor
protocol FreshnessMonitorProtocol: Sendable {
    /// Starts the periodic freshness check loop.
    func start() async
    /// Stops the freshness check loop by cancelling the internal task.
    func stop()
    /// Evaluates current data freshness and updates status message accordingly.
    func checkFreshness()
}
