import Foundation
import os

/// Periodically checks data freshness and sets a status message when data becomes very stale.
/// Runs every 15 seconds to detect staleness transitions promptly.
@MainActor
final class FreshnessMonitor: FreshnessMonitorProtocol {
    private let appState: AppState
    private var monitorTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "freshness"
    )

    static let defaultCheckInterval: TimeInterval = 15
    private let checkInterval: TimeInterval

    /// The title used for freshness status messages. Used to identify and clear our own messages.
    static let staleMessageTitle = "Data may be outdated"

    init(appState: AppState, checkInterval: TimeInterval = FreshnessMonitor.defaultCheckInterval) {
        self.appState = appState
        self.checkInterval = checkInterval
    }

    func start() async {
        Self.logger.info("Freshness monitor starting")
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.checkInterval ?? Self.defaultCheckInterval))
                guard !Task.isCancelled else { break }
                self?.checkFreshness()
            }
            Self.logger.info("Freshness monitor stopped")
        }
    }

    func stop() {
        Self.logger.info("Freshness monitor stopping")
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Internal (exposed for testing)

    /// Evaluates current data freshness and updates status message accordingly.
    func checkFreshness() {
        let freshness = appState.dataFreshness
        switch freshness {
        case .veryStale:
            let timeAgo = appState.lastUpdated?.relativeTimeAgo() ?? "unknown"
            appState.updateStatusMessage(StatusMessage(
                title: Self.staleMessageTitle,
                detail: "Last updated: \(timeAgo)"
            ))
            Self.logger.debug("Data is very stale — status message set")
        case .fresh, .stale:
            // Only clear if the current message is our stale message
            if appState.statusMessage?.title == Self.staleMessageTitle {
                appState.updateStatusMessage(nil)
                Self.logger.debug("Freshness recovered — cleared stale status message")
            }
        case .unknown:
            // Disconnected/no credentials — don't interfere with those status messages
            break
        }
    }
}
