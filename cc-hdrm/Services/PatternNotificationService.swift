import Foundation
import UserNotifications
import os

/// Delivers macOS notifications for actionable subscription pattern findings.
/// All findings except usageDecay trigger notifications. Tracks a 30-day
/// cooldown per finding type to prevent duplicate notifications.
@MainActor
final class PatternNotificationService: PatternNotificationServiceProtocol {
    private let notificationCenter: any NotificationCenterProtocol
    private let preferencesManager: any PreferencesManagerProtocol
    private let notificationService: any NotificationServiceProtocol

    /// Cooldown period in days before a finding type can re-notify.
    static let cooldownDays = 30

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "pattern-notification"
    )

    init(
        notificationCenter: any NotificationCenterProtocol,
        preferencesManager: any PreferencesManagerProtocol,
        notificationService: any NotificationServiceProtocol
    ) {
        self.notificationCenter = notificationCenter
        self.preferencesManager = preferencesManager
        self.notificationService = notificationService
    }

    func processFindings(_ findings: [PatternFinding]) async {
        guard notificationService.isAuthorized else {
            Self.logger.info("Notifications not authorized — skipping pattern notifications")
            return
        }

        for finding in findings {
            guard isNotifiableType(finding) else { continue }
            guard shouldNotify(finding) else {
                Self.logger.debug("Skipping notification for \(finding.cooldownKey, privacy: .public) — cooldown active")
                continue
            }

            await sendNotification(for: finding)

            var cooldowns = preferencesManager.patternNotificationCooldowns
            cooldowns[finding.cooldownKey] = Date()
            preferencesManager.patternNotificationCooldowns = cooldowns
            Self.logger.info("Pattern notification sent for \(finding.cooldownKey, privacy: .public)")
        }
    }

    /// Returns true if the finding type should trigger a macOS notification.
    private func isNotifiableType(_ finding: PatternFinding) -> Bool {
        switch finding {
        case .forgottenSubscription, .chronicOverpaying, .chronicUnderpowering,
             .extraUsageOverflow, .persistentExtraUsage:
            return true
        case .usageDecay:
            return false
        }
    }

    /// Returns true if the finding has not been notified within the cooldown period.
    private func shouldNotify(_ finding: PatternFinding) -> Bool {
        let cooldowns = preferencesManager.patternNotificationCooldowns
        guard let lastNotified = cooldowns[finding.cooldownKey] else { return true }
        let cooldownInterval = TimeInterval(Self.cooldownDays * 24 * 60 * 60)
        return Date().timeIntervalSince(lastNotified) >= cooldownInterval
    }

    /// Delivers a macOS notification for the finding.
    private func sendNotification(for finding: PatternFinding) async {
        let content = UNMutableNotificationContent()
        content.title = finding.title
        content.body = notificationBody(for: finding)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "pattern-\(finding.cooldownKey)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            Self.logger.error("Failed to deliver pattern notification: \(error.localizedDescription)")
        }
    }

    /// Returns the notification body text for a finding.
    private func notificationBody(for finding: PatternFinding) -> String {
        switch finding {
        case let .forgottenSubscription(weeks, _, _):
            return "You've used less than 5% of your Claude capacity for \(weeks) weeks. Worth reviewing?"
        case let .chronicOverpaying(_, recommendedTier, monthlySavings):
            return "Your usage fits \(recommendedTier) \u{2014} you could save $\(Int(monthlySavings))/mo"
        case let .chronicUnderpowering(rateLimitCount, _, suggestedTier):
            return "You've been rate-limited \(rateLimitCount) times recently. \(suggestedTier) would cover your usage."
        case let .extraUsageOverflow(avgExtraSpend, recommendedTier, _):
            return "You're averaging $\(String(format: "%.0f", avgExtraSpend))/mo in extra usage. Consider \(recommendedTier)."
        case let .persistentExtraUsage(avgMonthlyExtra, basePrice, recommendedTier):
            let pct = basePrice > 0 ? Int((avgMonthlyExtra / basePrice) * 100) : 0
            return "Extra usage is \(pct)% of your base plan. \(recommendedTier) may save you money."
        case .usageDecay:
            return finding.summary
        }
    }
}
