import Foundation
import Observation

/// The connection status of the application.
enum ConnectionStatus: String, Sendable {
    case connected
    case disconnected
    case tokenExpired
    case noCredentials
}

/// Represents the usage state for a single time window (5-hour or 7-day).
struct WindowState: Sendable, Equatable {
    let utilization: Double
    let resetsAt: Date?

    /// Headroom state is always derived from utilization, never stored separately.
    var headroomState: HeadroomState {
        HeadroomState(from: utilization)
    }
}

/// Single source of truth for all application state.
/// Views observe this directly. Services write via methods only.
@Observable
@MainActor
final class AppState {
    private(set) var fiveHour: WindowState?
    private(set) var sevenDay: WindowState?
    private(set) var connectionStatus: ConnectionStatus = .disconnected
    private(set) var lastUpdated: Date?
    private(set) var subscriptionTier: String?

    /// Updates the usage window states from API data.
    func updateWindows(fiveHour: WindowState?, sevenDay: WindowState?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.lastUpdated = Date()
    }

    /// Updates the connection status.
    func updateConnectionStatus(_ status: ConnectionStatus) {
        self.connectionStatus = status
    }

    /// Updates the subscription tier.
    func updateSubscriptionTier(_ tier: String?) {
        self.subscriptionTier = tier
    }
}
