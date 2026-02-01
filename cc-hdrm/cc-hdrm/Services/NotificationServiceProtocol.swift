/// Protocol for the notification service that manages macOS notification authorization.
@MainActor
protocol NotificationServiceProtocol: Sendable {
    /// Requests or checks notification authorization. On first launch, prompts the user;
    /// on subsequent launches, reads existing settings without re-prompting.
    func requestAuthorization() async
    /// Whether the app is currently authorized to post notifications.
    var isAuthorized: Bool { get }
}
