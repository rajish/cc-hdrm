import SwiftUI

/// Single-line context-aware summary below the subscription value bar.
/// Adapts insight text to the selected time range.
struct ContextAwareValueSummary: View {
    let timeRange: TimeRange
    let resetEvents: [ResetEvent]
    let allTimeResetEvents: [ResetEvent]
    let creditLimits: CreditLimits?
    let headroomAnalysisService: any HeadroomAnalysisServiceProtocol

    var body: some View {
        let insight = computeInsight()
        Text(insight.text)
            .font(.caption)
            .foregroundStyle(insight.isQuiet ? .tertiary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(insight.text)
    }

    private func computeInsight() -> ValueInsight {
        // Skip SubscriptionValue computation for .all range — allInsight computes its own monthly values
        let subscriptionValue: SubscriptionValue?
        if timeRange != .all, let limits = creditLimits {
            subscriptionValue = SubscriptionValueCalculator.calculate(
                resetEvents: resetEvents,
                creditLimits: limits,
                timeRange: timeRange,
                headroomAnalysisService: headroomAnalysisService
            )
        } else {
            subscriptionValue = nil
        }

        return ValueInsightEngine.computeInsight(
            timeRange: timeRange,
            subscriptionValue: subscriptionValue,
            resetEvents: resetEvents,
            allTimeResetEvents: allTimeResetEvents,
            creditLimits: creditLimits,
            headroomAnalysisService: headroomAnalysisService
        )
    }
}

#if DEBUG
#Preview("Day - Dollar") {
    ContextAwareValueSummary(
        timeRange: .day,
        resetEvents: previewEvents(count: 2, spanDays: 1),
        allTimeResetEvents: previewEvents(count: 30, spanDays: 90),
        creditLimits: RateLimitTier.pro.creditLimits,
        headroomAnalysisService: PreviewValueSummaryService()
    )
    .padding()
}

#Preview("Week - Above Average") {
    ContextAwareValueSummary(
        timeRange: .week,
        resetEvents: previewEvents(count: 5, spanDays: 7),
        allTimeResetEvents: previewEvents(count: 30, spanDays: 90),
        creditLimits: RateLimitTier.pro.creditLimits,
        headroomAnalysisService: PreviewValueSummaryService()
    )
    .padding()
}

#Preview("Month - Dollar") {
    ContextAwareValueSummary(
        timeRange: .month,
        resetEvents: previewEvents(count: 15, spanDays: 30),
        allTimeResetEvents: previewEvents(count: 30, spanDays: 90),
        creditLimits: RateLimitTier.pro.creditLimits,
        headroomAnalysisService: PreviewValueSummaryService()
    )
    .padding()
}

#Preview("All - Trend") {
    ContextAwareValueSummary(
        timeRange: .all,
        resetEvents: previewEvents(count: 30, spanDays: 90),
        allTimeResetEvents: previewEvents(count: 30, spanDays: 90),
        creditLimits: RateLimitTier.pro.creditLimits,
        headroomAnalysisService: PreviewValueSummaryService()
    )
    .padding()
}

#Preview("No Events") {
    ContextAwareValueSummary(
        timeRange: .week,
        resetEvents: [],
        allTimeResetEvents: [],
        creditLimits: RateLimitTier.pro.creditLimits,
        headroomAnalysisService: PreviewValueSummaryService()
    )
    .padding()
}

private func previewEvents(count: Int, spanDays: Int) -> [ResetEvent] {
    let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    let totalSpanMs: Int64 = Int64(spanDays) * 24 * 3_600_000
    let stepMs: Int64 = count > 1 ? totalSpanMs / Int64(count - 1) : 0
    var events: [ResetEvent] = []
    for i in 0..<count {
        let ts: Int64 = nowMs - totalSpanMs + Int64(i) * stepMs
        events.append(ResetEvent(
            id: Int64(i + 1),
            timestamp: ts,
            fiveHourPeak: 50.0 + Double(i % 10),
            sevenDayUtil: 40.0 + Double(i % 5),
            tier: "default_claude_pro",
            usedCredits: nil,
            constrainedCredits: nil,
            unusedCredits: nil
        ))
    }
    return events
}

private struct PreviewValueSummaryService: HeadroomAnalysisServiceProtocol {
    func analyzeResetEvent(fiveHourPeak: Double, sevenDayUtil: Double, creditLimits: CreditLimits) -> HeadroomBreakdown {
        HeadroomBreakdown(usedPercent: 52, constrainedPercent: 12, unusedPercent: 36,
                          usedCredits: 286_000, constrainedCredits: 66_000, unusedCredits: 198_000)
    }

    func aggregateBreakdown(events: [ResetEvent]) -> PeriodSummary {
        PeriodSummary(usedCredits: 2_860_000, constrainedCredits: 660_000, unusedCredits: 1_980_000,
                      resetCount: events.count, avgPeakUtilization: 52.0,
                      usedPercent: 52, constrainedPercent: 12, unusedPercent: 36)
    }
}
#endif
