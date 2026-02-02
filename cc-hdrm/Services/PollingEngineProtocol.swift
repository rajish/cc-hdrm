/// Protocol for the background polling engine that fetches usage data on a schedule.
@MainActor
protocol PollingEngineProtocol: Sendable {
    /// Starts the polling loop. Performs an initial fetch immediately, then polls every 30 seconds.
    func start() async
    /// Stops the polling loop by cancelling the internal task.
    func stop()
}
