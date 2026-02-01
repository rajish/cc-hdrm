/// Threshold state for a single time window's headroom level.
/// Tracks whether warning/critical notifications have been fired to enforce fire-once semantics.
enum ThresholdState: String, Sendable {
    /// Headroom >= 20%, both thresholds armed.
    case aboveWarning
    /// Warning fired, headroom < 20%, critical armed.
    case warned20
    /// Critical fired (Story 5.3), headroom < 5%.
    case warned5
}

/// Protocol for the notification service that manages macOS notification authorization
/// and threshold-based notification delivery.
@MainActor
protocol NotificationServiceProtocol: Sendable {
    /// Requests or checks notification authorization. On first launch, prompts the user;
    /// on subsequent launches, reads existing settings without re-prompting.
    func requestAuthorization() async
    /// Whether the app is currently authorized to post notifications.
    var isAuthorized: Bool { get }

    /// Evaluates headroom thresholds for both windows and fires notifications on crossings.
    func evaluateThresholds(fiveHour: WindowState?, sevenDay: WindowState?) async

    /// Current threshold state for 5-hour window (read-only, for testing).
    var fiveHourThresholdState: ThresholdState { get }
    /// Current threshold state for 7-day window (read-only, for testing).
    var sevenDayThresholdState: ThresholdState { get }
}
