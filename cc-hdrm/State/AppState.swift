import Foundation
import Observation
import os

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

/// Which time window is currently promoted to the menu bar display.
enum DisplayedWindow: Sendable, Equatable {
    case fiveHour
    case sevenDay
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
    private(set) var availableUpdate: AvailableUpdate?
    private(set) var fiveHourSlope: SlopeLevel = .flat
    private(set) var sevenDaySlope: SlopeLevel = .flat

    /// Counter incremented every 60 seconds to trigger observation-based re-renders of countdown text.
    private(set) var countdownTick: UInt = 0

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "menubar"
    )

    /// Derived data freshness based on `lastUpdated` and `connectionStatus`.
    /// When disconnected, always returns `.unknown` regardless of `lastUpdated`.
    var dataFreshness: DataFreshness {
        guard connectionStatus == .connected else {
            return .unknown
        }
        return DataFreshness(lastUpdated: lastUpdated)
    }

    /// Which window is currently displayed in the menu bar.
    /// 7-day promotes when it has lower headroom AND is in warning or critical state.
    var displayedWindow: DisplayedWindow {
        guard connectionStatus == .connected, fiveHour != nil else {
            return .fiveHour
        }

        let fiveHourHeadroom = 100.0 - (fiveHour?.utilization ?? 100.0)
        let sevenDayHeadroom = 100.0 - (sevenDay?.utilization ?? 100.0)

        if let sevenDayState = sevenDay?.headroomState,
           (sevenDayState == .warning || sevenDayState == .critical),
           sevenDayHeadroom < fiveHourHeadroom {
            return .sevenDay
        }

        return .fiveHour
    }

    /// Derived headroom state for the menu bar display.
    /// Returns `.disconnected` when not connected; promotes 7-day when tighter constraint applies.
    var menuBarHeadroomState: HeadroomState {
        guard connectionStatus == .connected else {
            return .disconnected
        }

        switch displayedWindow {
        case .fiveHour:
            return fiveHour?.headroomState ?? .disconnected
        case .sevenDay:
            return sevenDay?.headroomState ?? .disconnected
        }
    }

    /// The slope level for the currently displayed window.
    /// Returns fiveHourSlope when 5h window is displayed, sevenDaySlope when 7d is promoted.
    var displayedSlope: SlopeLevel {
        switch displayedWindow {
        case .fiveHour:
            return fiveHourSlope
        case .sevenDay:
            return sevenDaySlope
        }
    }

    /// Derived menu bar text: headroom percentage, countdown, or em dash when disconnected.
    /// Appends slope arrow when slope is actionable (rising/steep) and not in exhausted state.
    /// Note: Sparkle icon removed — gauge icon now provides the visual indicator.
    var menuBarText: String {
        if menuBarHeadroomState == .disconnected {
            return "\u{2014}" // — (em dash only)
        }

        let window: WindowState? = displayedWindow == .fiveHour ? fiveHour : sevenDay

        if let window, window.headroomState == .exhausted, let resetsAt = window.resetsAt {
            // Access countdownTick to register with withObservationTracking
            _ = countdownTick
            return "\u{21BB} \(resetsAt.countdownString())" // ↻ Xm
        }

        let headroom = max(0, Int(100.0 - (window?.utilization ?? 0)))
        let slope = displayedSlope

        // Append slope arrow only when actionable (rising/steep) AND not exhausted
        // Per edge case #5: exhausted without resetsAt shows percentage only, no slope
        if slope.isActionable && window?.headroomState != .exhausted {
            return "\(headroom)% \(slope.arrow)"
        }
        return "\(headroom)%"
    }

    /// Increments the countdown tick to trigger observation-based re-renders.
    /// Called every 60 seconds by FreshnessMonitor or AppDelegate.
    func tickCountdown() {
        countdownTick &+= 1
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

    /// Updates or clears the available update info.
    func updateAvailableUpdate(_ update: AvailableUpdate?) {
        self.availableUpdate = update
    }

    /// Updates the slope levels for both time windows.
    func updateSlopes(fiveHour: SlopeLevel, sevenDay: SlopeLevel) {
        self.fiveHourSlope = fiveHour
        self.sevenDaySlope = sevenDay
    }

    /// Sets `lastUpdated` to an arbitrary date. Test use only — not available in release builds.
    #if DEBUG
    func setLastUpdated(_ date: Date?) {
        self.lastUpdated = date
    }
    #endif
}
