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
    private(set) var creditLimits: CreditLimits?

    // MARK: - Extra Usage State (Story 17.1)
    private(set) var extraUsageEnabled: Bool = false
    /// Monthly extra usage limit in cents. Use `formatCents(_:)` for display.
    private(set) var extraUsageMonthlyLimitCents: Int?
    /// Extra usage spent this period in cents. Use `formatCents(_:)` for display.
    private(set) var extraUsageUsedCreditsCents: Int?
    private(set) var extraUsageUtilization: Double?

    /// User-configured billing cycle day (1-28), nil if unset.
    /// Mirrored from PreferencesManager so SwiftUI views can observe changes reactively.
    private(set) var billingCycleDay: Int?

    /// Whether the analytics window is currently open.
    /// Updated by AnalyticsWindow on window open/close.
    private(set) var isAnalyticsWindowOpen: Bool = false

    /// Poll data for the 24h sparkline visualization. Updated on each successful poll cycle.
    /// Data is ordered by timestamp ascending. Preserved across connection state changes.
    private(set) var sparklineData: [UsagePoll] = []

    /// Minimum data points required for sparkline rendering.
    static let sparklineMinDataPoints = 2

    /// Whether enough sparkline data exists for rendering (minimum 2 data points for a line).
    var hasSparklineData: Bool {
        sparklineData.count >= Self.sparklineMinDataPoints
    }

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

    /// How many full 5h quotas remain in the 7d budget. Nil when credit limits are unavailable
    /// or when `fiveHourCredits` is zero (defensive guard — prevents inf propagation).
    var quotasRemaining: Double? {
        guard let limits = creditLimits,
              limits.fiveHourCredits > 0,
              let sevenDay else { return nil }
        let remaining7d = (100.0 - sevenDay.utilization) / 100.0 * Double(limits.sevenDayCredits)
        return remaining7d / Double(limits.fiveHourCredits)
    }

    /// Which window is currently displayed in the menu bar.
    /// Credit-math path: promotes 7d only when remaining 7d credits can't sustain one more full 5h cycle.
    /// Fallback path (unknown tier): uses Story 3.2 percentage-comparison rule.
    var displayedWindow: DisplayedWindow {
        guard connectionStatus == .connected, fiveHour != nil else {
            return .fiveHour
        }

        // Exhausted countdown always takes precedence over 7d promotion
        if fiveHour?.headroomState == .exhausted { return .fiveHour }

        // Credit-math path (when tier is known)
        if let quotas = quotasRemaining {
            return quotas < 1.0 ? .sevenDay : .fiveHour
        }

        // Fallback: Story 3.2 percentage-comparison rule (unknown tier)
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

    /// Whether extra usage mode is active: enabled AND at least one window exhausted.
    var isExtraUsageActive: Bool {
        guard extraUsageEnabled else { return false }
        let fiveHourExhausted = fiveHour?.headroomState == .exhausted
        let sevenDayExhausted = sevenDay?.headroomState == .exhausted
        return fiveHourExhausted || sevenDayExhausted
    }

    /// Remaining prepaid extra usage balance in cents. Nil when monthly limit or used credits unknown.
    var extraUsageRemainingBalanceCents: Int? {
        guard let limit = extraUsageMonthlyLimitCents, let used = extraUsageUsedCreditsCents else { return nil }
        return limit - used
    }

    /// Formats a cent amount as a currency string using integer math (no floating-point).
    /// Example: `formatCents(1561)` → `"$15.61"`, `formatCents(-300)` → `"-$3.00"`.
    nonisolated static func formatCents(_ cents: Int, symbol: String = "$") -> String {
        let absCents = abs(cents)
        let dollars = absCents / 100
        let remainder = absCents % 100
        let prefix = cents < 0 ? "-" : ""
        return String(format: "%@%@%d.%02d", prefix, symbol, dollars, remainder)
    }

    /// Menu bar text for extra usage mode. Returns formatted currency when active, nil otherwise.
    var menuBarExtraUsageText: String? {
        guard isExtraUsageActive else { return nil }
        if let remaining = extraUsageRemainingBalanceCents {
            return Self.formatCents(remaining)
        } else if let used = extraUsageUsedCreditsCents {
            return "\(Self.formatCents(used)) spent"
        }
        return "$0.00"
    }

    /// Derived menu bar text: headroom percentage, countdown, or em dash when disconnected.
    /// Appends slope arrow when slope is actionable (rising/steep) and not in exhausted state.
    /// Note: Sparkle icon removed — gauge icon now provides the visual indicator.
    var menuBarText: String {
        if menuBarHeadroomState == .disconnected {
            return "\u{2014}" // — (em dash only)
        }

        // Extra usage mode: show currency instead of headroom
        if let extraText = menuBarExtraUsageText {
            return extraText
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

    /// Updates the resolved credit limits from the current tier.
    /// Called by PollingEngine after resolving tier from Keychain credentials each poll cycle.
    func updateCreditLimits(_ limits: CreditLimits?) {
        self.creditLimits = limits
    }

    /// Updates the slope levels for both time windows.
    func updateSlopes(fiveHour: SlopeLevel, sevenDay: SlopeLevel) {
        self.fiveHourSlope = fiveHour
        self.sevenDaySlope = sevenDay
    }

    /// Updates extra usage billing state from API data.
    /// Monetary values from the API arrive as Double (cents). Converted to Int at this boundary.
    func updateExtraUsage(enabled: Bool, monthlyLimit: Double?, usedCredits: Double?, utilization: Double?) {
        self.extraUsageEnabled = enabled
        self.extraUsageMonthlyLimitCents = monthlyLimit.map { Int($0.rounded()) }
        self.extraUsageUsedCreditsCents = usedCredits.map { Int($0.rounded()) }
        self.extraUsageUtilization = utilization
    }

    /// Updates the sparkline data from recent polls.
    /// - Parameter data: Poll data ordered by timestamp ascending from HistoricalDataService
    func updateSparklineData(_ data: [UsagePoll]) {
        self.sparklineData = data
    }

    /// Sets the analytics window open state.
    /// Called by AnalyticsWindow when window opens or closes.
    func setAnalyticsWindowOpen(_ open: Bool) {
        self.isAnalyticsWindowOpen = open
    }

    /// Updates the billing cycle day from preferences.
    /// Called when the user changes the setting so SwiftUI views update reactively.
    func updateBillingCycleDay(_ day: Int?) {
        self.billingCycleDay = day
    }

    /// Sets `lastUpdated` to an arbitrary date. Test use only — not available in release builds.
    #if DEBUG
    func setLastUpdated(_ date: Date?) {
        self.lastUpdated = date
    }
    #endif
}
