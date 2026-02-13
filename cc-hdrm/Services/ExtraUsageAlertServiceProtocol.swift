/// Protocol for the extra usage alert service that evaluates spending thresholds
/// and delivers macOS notifications when thresholds are crossed (Story 17.4).
@MainActor
protocol ExtraUsageAlertServiceProtocol {
    func evaluateExtraUsageThresholds(
        extraUsageEnabled: Bool,
        utilization: Double?,
        usedCreditsCents: Int?,
        monthlyLimitCents: Int?,
        billingCycleDay: Int?,
        planExhausted: Bool
    ) async
}
