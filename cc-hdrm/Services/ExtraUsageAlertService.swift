import Foundation
import UserNotifications
import os

/// Evaluates extra usage spending thresholds on each poll cycle and delivers
/// macOS notifications when thresholds are crossed. Tracks fired thresholds
/// per billing period and re-arms on period reset (Story 17.4).
@MainActor
final class ExtraUsageAlertService: ExtraUsageAlertServiceProtocol {
    private let notificationCenter: any NotificationCenterProtocol
    private let notificationService: any NotificationServiceProtocol
    private let preferencesManager: any PreferencesManagerProtocol

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "extra-usage-alerts"
    )

    init(
        notificationCenter: any NotificationCenterProtocol,
        notificationService: any NotificationServiceProtocol,
        preferencesManager: any PreferencesManagerProtocol
    ) {
        self.notificationCenter = notificationCenter
        self.notificationService = notificationService
        self.preferencesManager = preferencesManager
    }

    func evaluateExtraUsageThresholds(
        extraUsageEnabled: Bool,
        utilization: Double?,
        usedCredits: Double?,
        monthlyLimit: Double?,
        billingCycleDay: Int?,
        planExhausted: Bool
    ) async {
        // Guard: no extra usage on account
        guard extraUsageEnabled else { return }

        // Guard: master toggle off
        guard preferencesManager.extraUsageAlertsEnabled else { return }

        // Guard: no utilization data
        guard let utilization else { return }

        // Check billing period reset and re-arm if needed
        let currentPeriodKey = Self.computeBillingPeriodKey(billingCycleDay: billingCycleDay)
        if preferencesManager.extraUsageLastBillingPeriodKey != currentPeriodKey {
            Self.logger.info("Billing period changed to \(currentPeriodKey, privacy: .public) — re-arming thresholds")
            preferencesManager.extraUsageFiredThresholds = []
            preferencesManager.extraUsageEnteredAlertFired = false
            preferencesManager.extraUsageLastBillingPeriodKey = currentPeriodKey
        }

        // Evaluate "entered extra usage" alert
        if planExhausted
            && !preferencesManager.extraUsageEnteredAlertFired
            && preferencesManager.extraUsageEnteredAlertEnabled {
            await deliverNotification(
                title: "Extra usage started",
                body: "Your plan quota is exhausted \u{2014} extra usage is now active",
                identifier: "extra-usage-entered"
            )
            preferencesManager.extraUsageEnteredAlertFired = true
        }

        // Evaluate threshold alerts (50%, 75%, 90%) from lowest to highest
        let thresholds: [(percent: Int, keyPath: KeyPath<PreferencesManagerProtocol, Bool>)] = [
            (50, \.extraUsageThreshold50Enabled),
            (75, \.extraUsageThreshold75Enabled),
            (90, \.extraUsageThreshold90Enabled),
        ]

        let utilizationPercent = utilization * 100.0
        var firedThresholds = preferencesManager.extraUsageFiredThresholds

        // Convert raw API cents (Double) to Int once for notification text
        let usedCents = Int((usedCredits ?? 0).rounded())
        let limitCents = Int((monthlyLimit ?? 0).rounded())

        for (percent, toggleKeyPath) in thresholds {
            guard preferencesManager[keyPath: toggleKeyPath] else { continue }
            guard utilizationPercent >= Double(percent) else { continue }
            guard !firedThresholds.contains(percent) else { continue }

            let (title, body) = thresholdNotificationText(
                percent: percent,
                usedCents: usedCents,
                limitCents: limitCents
            )
            await deliverNotification(
                title: title,
                body: body,
                identifier: "extra-usage-threshold-\(percent)"
            )
            firedThresholds.insert(percent)
        }

        preferencesManager.extraUsageFiredThresholds = firedThresholds
    }

    // MARK: - Billing Period Key

    static func computeBillingPeriodKey(billingCycleDay: Int?, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let day = billingCycleDay ?? 1
        let currentDay = calendar.component(.day, from: now)
        var year = calendar.component(.year, from: now)
        var month = calendar.component(.month, from: now)
        // If we haven't reached the billing day yet, we're in the previous period
        if currentDay < day {
            month -= 1
            if month < 1 { month = 12; year -= 1 }
        }
        return String(format: "%04d-%02d", year, month)
    }

    // MARK: - Notification Text

    private func thresholdNotificationText(
        percent: Int,
        usedCents: Int,
        limitCents: Int
    ) -> (title: String, body: String) {
        let usedText = AppState.formatCents(max(0, usedCents))
        let limitText = AppState.formatCents(max(0, limitCents))

        switch percent {
        case 50:
            return (
                "Extra usage update",
                "You've used half your extra usage budget (\(usedText) of \(limitText))"
            )
        case 75:
            return (
                "Extra usage warning",
                "Extra usage at 75% \u{2014} \(usedText) of \(limitText) spent this period"
            )
        case 90:
            let remainingCents = max(0, limitCents - usedCents)
            return (
                "Extra usage alert",
                "Extra usage at 90% \u{2014} \(AppState.formatCents(remainingCents)) left before hitting your monthly limit"
            )
        default:
            return ("Extra usage alert", "Extra usage at \(percent)%")
        }
    }

    // MARK: - Notification Delivery

    private func deliverNotification(title: String, body: String, identifier: String) async {
        guard notificationService.isAuthorized else {
            Self.logger.info("Skipping extra usage notification — not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(identifier)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
            Self.logger.info("Extra usage notification delivered: \(title, privacy: .public)")
        } catch {
            Self.logger.error("Failed to deliver extra usage notification: \(error.localizedDescription)")
        }
    }
}
