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

/// A user-facing status message with title and detail text.
struct StatusMessage: Sendable, Equatable {
    let title: String
    let detail: String
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
    private(set) var statusMessage: StatusMessage?

    /// Derived data freshness based on `lastUpdated` and `connectionStatus`.
    /// When disconnected, always returns `.unknown` regardless of `lastUpdated`.
    var dataFreshness: DataFreshness {
        guard connectionStatus == .connected else {
            return .unknown
        }
        return DataFreshness(lastUpdated: lastUpdated)
    }

    /// Derived headroom state for the menu bar display.
    /// Returns `.disconnected` when not connected; otherwise derived from 5-hour window.
    var menuBarHeadroomState: HeadroomState {
        guard connectionStatus == .connected else {
            return .disconnected
        }
        return fiveHour?.headroomState ?? .disconnected
    }

    /// Derived menu bar text: sparkle icon + headroom percentage or em dash when disconnected.
    var menuBarText: String {
        if menuBarHeadroomState == .disconnected {
            return "\u{2733} \u{2014}" // ✳ —
        }
        let headroom = max(0, Int(100.0 - (fiveHour?.utilization ?? 0)))
        return "\u{2733} \(headroom)%"
    }

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

    /// Updates or clears the status message shown to the user.
    func updateStatusMessage(_ message: StatusMessage?) {
        self.statusMessage = message
    }

    /// Sets `lastUpdated` to an arbitrary date. Test use only — not available in release builds.
    #if DEBUG
    func setLastUpdated(_ date: Date?) {
        self.lastUpdated = date
    }
    #endif
}
