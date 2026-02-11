import SwiftUI

/// Horizontal bar showing subscription usage breakdown.
///
/// Display modes:
/// - **Dollar breakdown**: Used/unused dollar amounts with color-coded segments (known tier with price)
/// - **Percentage-only**: Used/unused percentages without dollar amounts (custom limits, no price)
/// - **Qualifier mode**: Percentage-only with data qualifier text (insufficient data for dollar proration)
///
/// Falls back to informational text when creditLimits is nil or resetEvents is empty.
struct HeadroomBreakdownBar: View {
    let resetEvents: [ResetEvent]
    let creditLimits: CreditLimits?
    let headroomAnalysisService: any HeadroomAnalysisServiceProtocol
    let selectedTimeRange: TimeRange
    var dataQualifier: String? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)

            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
    }

    @ViewBuilder
    private var content: some View {
        if creditLimits == nil {
            Text("Subscription breakdown unavailable -- unknown subscription tier")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Subscription breakdown unavailable -- unknown subscription tier")
        } else if resetEvents.isEmpty {
            Text("No reset events in this period")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("No reset events in this period")
        } else if dataQualifier != nil {
            qualifierContent
        } else {
            breakdownContent
        }
    }

    @ViewBuilder
    private var breakdownContent: some View {
        let limits = creditLimits!
        let subscriptionValue = SubscriptionValueCalculator.calculate(
            resetEvents: resetEvents,
            creditLimits: limits,
            timeRange: selectedTimeRange,
            headroomAnalysisService: headroomAnalysisService
        )

        if let value = subscriptionValue {
            dollarBreakdown(value: value)
        } else {
            // Custom limits without monthlyPrice — show percentage-only mode
            percentageOnlyBreakdown(limits: limits)
        }
    }

    // MARK: - Dollar Breakdown (known tier with price)

    @ViewBuilder
    private func dollarBreakdown(value: SubscriptionValue) -> some View {
        let usedFraction = value.utilizationPercent / 100.0
        let unusedFraction = 1.0 - usedFraction
        let usedColor = HeadroomState(from: value.utilizationPercent).swiftUIColor

        VStack(spacing: 6) {
            // Dollar annotation
            HStack {
                Text("\(SubscriptionValueCalculator.formatDollars(value.usedDollars)) used")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                Text("of \(SubscriptionValueCalculator.formatDollars(value.periodPrice))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Stacked bar
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Used segment — solid fill
                    if usedFraction > 0 {
                        Rectangle()
                            .fill(usedColor)
                            .frame(width: max(0, geometry.size.width * usedFraction))
                    }

                    // Unused segment — light fill
                    if unusedFraction > 0 {
                        ZStack {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.08))
                            Rectangle()
                                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                        }
                        .frame(width: max(0, geometry.size.width * unusedFraction))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 24)

            // Legend
            dollarLegend(value: value, usedColor: usedColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subscription usage: \(SubscriptionValueCalculator.formatDollars(value.usedDollars)) used of \(SubscriptionValueCalculator.formatDollars(value.periodPrice)), \(Int(value.utilizationPercent.rounded()))% utilization")
    }

    // MARK: - Percentage-Only Breakdown (custom limits, no price)

    @ViewBuilder
    private func percentageOnlyBreakdown(limits: CreditLimits) -> some View {
        let utilizationPercent = percentageOnlyUtilization(limits: limits)

        percentageOnlyBarAndLegend(utilizationPercent: utilizationPercent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Subscription usage: \(Int(utilizationPercent.rounded()))% utilization")
    }

    // MARK: - Qualifier Content (insufficient data for dollar proration)

    @ViewBuilder
    private var qualifierContent: some View {
        if let limits = creditLimits, let qualifier = dataQualifier {
            let utilizationPercent = percentageOnlyUtilization(limits: limits)

            VStack(spacing: 4) {
                Text(qualifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                percentageOnlyBarAndLegend(utilizationPercent: utilizationPercent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(qualifier). Subscription usage: \(Int(utilizationPercent.rounded()))% utilization")
        }
    }

    // MARK: - Shared Percentage Bar + Legend (no padding)

    @ViewBuilder
    private func percentageOnlyBarAndLegend(utilizationPercent: Double) -> some View {
        let usedFraction = utilizationPercent / 100.0
        let unusedFraction = 1.0 - usedFraction
        let usedColor = HeadroomState(from: utilizationPercent).swiftUIColor

        VStack(spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if usedFraction > 0 {
                        Rectangle()
                            .fill(usedColor)
                            .frame(width: max(0, geometry.size.width * usedFraction))
                    }
                    if unusedFraction > 0 {
                        ZStack {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.08))
                            Rectangle()
                                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                        }
                        .frame(width: max(0, geometry.size.width * unusedFraction))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 24)

            percentageLegend(utilizationPercent: utilizationPercent, usedColor: usedColor)
        }
    }

    /// Computes utilization percentage for percentage-only display mode.
    private func percentageOnlyUtilization(limits: CreditLimits) -> Double {
        let summary = headroomAnalysisService.aggregateBreakdown(events: resetEvents)
        let periodDays = SubscriptionValueCalculator.periodDays(for: selectedTimeRange, events: resetEvents)
        let totalAvailable = Double(limits.sevenDayCredits) * (periodDays / 7.0)
        return totalAvailable > 0 ? min(100.0, (summary.usedCredits / totalAvailable) * 100.0) : 0
    }

    // MARK: - Legends

    @ViewBuilder
    private func dollarLegend(value: SubscriptionValue, usedColor: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                legendSwatch(color: usedColor, style: .solid)
                Text("Used: \(SubscriptionValueCalculator.formatDollars(value.usedDollars)) (\(Int(value.utilizationPercent.rounded()))%)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                legendSwatch(color: Color.secondary.opacity(0.15), style: .outlined)
                Text("Unused: \(SubscriptionValueCalculator.formatDollars(value.unusedDollars)) (\(Int((100.0 - value.utilizationPercent).rounded()))%)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("of \(SubscriptionValueCalculator.formatDollars(value.periodPrice)) (prorated from \(SubscriptionValueCalculator.formatDollars(value.monthlyPrice))/mo)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func percentageLegend(utilizationPercent: Double, usedColor: Color) -> some View {
        HStack(spacing: 0) {
            legendSwatch(color: usedColor, style: .solid)
            Text("Used: \(Int(utilizationPercent.rounded()))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            legendSwatch(color: Color.secondary.opacity(0.15), style: .outlined)
            Text("Unused: \(Int((100.0 - utilizationPercent).rounded()))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private enum SwatchStyle {
        case solid
        case outlined
    }

    @ViewBuilder
    private func legendSwatch(color: Color, style: SwatchStyle) -> some View {
        Group {
            switch style {
            case .solid:
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
            case .outlined:
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
            }
        }
        .frame(width: 10, height: 10)
        .padding(.trailing, 4)
    }
}

#if DEBUG
private let previewEvents: [ResetEvent] = {
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    return (0..<5).map { i in
        ResetEvent(
            id: Int64(i + 1),
            timestamp: nowMs - Int64(i) * 3_600_000,
            fiveHourPeak: 60.0 + Double(i) * 5,
            sevenDayUtil: 30.0 + Double(i) * 3,
            tier: "default_claude_pro",
            usedCredits: nil,
            constrainedCredits: nil,
            unusedCredits: nil
        )
    }
}()

#Preview {
    VStack(spacing: 12) {
        // Dollar bar (known tier with events)
        HeadroomBreakdownBar(
            resetEvents: previewEvents,
            creditLimits: RateLimitTier.pro.creditLimits,
            headroomAnalysisService: PreviewHeadroomAnalysisService(),
            selectedTimeRange: .week
        )
        // Empty events fallback
        HeadroomBreakdownBar(
            resetEvents: [],
            creditLimits: RateLimitTier.pro.creditLimits,
            headroomAnalysisService: PreviewHeadroomAnalysisService(),
            selectedTimeRange: .week
        )
        // Nil creditLimits fallback
        HeadroomBreakdownBar(
            resetEvents: previewEvents,
            creditLimits: nil,
            headroomAnalysisService: PreviewHeadroomAnalysisService(),
            selectedTimeRange: .week
        )
    }
    .padding()
    .frame(width: 600)
}

/// Minimal preview-only stub for HeadroomAnalysisServiceProtocol.
private struct PreviewHeadroomAnalysisService: HeadroomAnalysisServiceProtocol {
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
