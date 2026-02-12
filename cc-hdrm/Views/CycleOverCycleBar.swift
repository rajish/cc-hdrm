import Charts
import SwiftUI

/// Compact cycle-over-cycle bar chart showing utilization per billing cycle (or calendar month).
/// Renders only for `.month` and `.all` time ranges with 3+ cycles.
/// Height is fixed at 60px — it's a trend indicator, not a full chart.
struct CycleOverCycleBar: View {
    let cycles: [CycleUtilization]
    let timeRange: TimeRange

    @State private var hoveredCycle: CycleUtilization?

    var body: some View {
        if shouldRender {
            chartContent
                .frame(height: 60)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Usage trend over \(cycles.count) months. \(trendSummary).")
                .accessibilityHint("Double-tap for details")
        }
    }

    private var shouldRender: Bool {
        (timeRange == .month || timeRange == .all) && cycles.count >= 3
    }

    // MARK: - Chart Content

    private var chartContent: some View {
        Chart(cycles) { cycle in
            BarMark(
                x: .value("Month", cycle.id),
                y: .value("Utilization", cycle.utilizationPercent)
            )
            .foregroundStyle(cycle.isPartial ? Color.headroomNormal.opacity(0.4) : Color.headroomNormal)
            .accessibilityLabel(accessibilityLabel(for: cycle))
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            if cycles.count <= 12 {
                AxisMarks(values: .automatic) { value in
                    if let id = value.as(String.self), let cycle = cycles.first(where: { $0.id == id }) {
                        AxisValueLabel {
                            Text(cycle.label)
                                .font(.system(size: 9))
                        }
                    }
                }
            } else {
                AxisMarks(values: .automatic) { _ in }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoveredCycle = findCycle(at: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            hoveredCycle = nil
                        }
                    }
                    .overlay(alignment: .top) {
                        tooltipView
                    }
            }
        }
    }

    // MARK: - Tooltip

    @ViewBuilder
    private var tooltipView: some View {
        if let cycle = hoveredCycle {
            VStack(spacing: 2) {
                Text("\(fullMonthName(cycle.label)) \(String(cycle.year))")
                    .font(.caption2)
                    .fontWeight(.semibold)
                Text("\(Int(cycle.utilizationPercent))% utilization")
                    .font(.caption2)
                if let dollars = cycle.dollarValue, cycle.utilizationPercent > 0 {
                    let total = dollars / (cycle.utilizationPercent / 100.0)
                    Text("\(SubscriptionValueCalculator.formatDollars(dollars)) of \(SubscriptionValueCalculator.formatDollars(total))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let dollars = cycle.dollarValue {
                    Text(SubscriptionValueCalculator.formatDollars(dollars))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Hover Detection

    private func findCycle(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> CycleUtilization? {
        // Use proxy.value(atX:) to resolve the hovered cycle ID from the string-keyed x-axis
        guard let hoveredID: String = proxy.value(atX: location.x) else { return nil }
        return cycles.first { $0.id == hoveredID }
    }

    // MARK: - Accessibility

    private var trendSummary: String {
        let complete = cycles.filter { !$0.isPartial }
        guard complete.count >= 3 else { return "Insufficient data for trend" }

        let lastThree = Array(complete.suffix(3))
        let allRising = lastThree[1].utilizationPercent - lastThree[0].utilizationPercent > 5.0
            && lastThree[2].utilizationPercent - lastThree[1].utilizationPercent > 5.0
        let allFalling = lastThree[0].utilizationPercent - lastThree[1].utilizationPercent > 5.0
            && lastThree[1].utilizationPercent - lastThree[2].utilizationPercent > 5.0

        if allRising { return "Trending up" }
        if allFalling { return "Trending down" }
        return "Stable"
    }

    private func accessibilityLabel(for cycle: CycleUtilization) -> String {
        var parts = ["\(fullMonthName(cycle.label)) \(cycle.year)", "\(Int(cycle.utilizationPercent)) percent utilization"]
        if let dollars = cycle.dollarValue, cycle.utilizationPercent > 0 {
            let total = dollars / (cycle.utilizationPercent / 100.0)
            parts.append("\(SubscriptionValueCalculator.formatDollars(dollars)) of \(SubscriptionValueCalculator.formatDollars(total))")
        } else if let dollars = cycle.dollarValue {
            parts.append(SubscriptionValueCalculator.formatDollars(dollars))
        }
        return parts.joined(separator: ", ")
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private func fullMonthName(_ abbreviation: String) -> String {
        if let index = Self.monthFormatter.shortMonthSymbols.firstIndex(of: abbreviation) {
            return Self.monthFormatter.monthSymbols[index]
        }
        return abbreviation
    }
}

#if DEBUG
#Preview("Trending Up — 6 months") {
    CycleOverCycleBar(
        cycles: [
            CycleUtilization(label: "Sep", year: 2025, utilizationPercent: 30, dollarValue: 6, isPartial: false, resetCount: 5),
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 45, dollarValue: 9, isPartial: false, resetCount: 8),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 55, dollarValue: 11, isPartial: false, resetCount: 10),
            CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 68, dollarValue: 13.60, isPartial: false, resetCount: 12),
            CycleUtilization(label: "Jan", year: 2026, utilizationPercent: 82, dollarValue: 16.40, isPartial: false, resetCount: 14),
            CycleUtilization(label: "Feb", year: 2026, utilizationPercent: 40, dollarValue: 8, isPartial: true, resetCount: 4),
        ],
        timeRange: .all
    )
    .padding()
    .frame(width: 500)
}

#Preview("Trending Down — 5 months") {
    CycleOverCycleBar(
        cycles: [
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 90, dollarValue: 18, isPartial: false, resetCount: 15),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 75, dollarValue: 15, isPartial: false, resetCount: 12),
            CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 55, dollarValue: 11, isPartial: false, resetCount: 9),
            CycleUtilization(label: "Jan", year: 2026, utilizationPercent: 35, dollarValue: 7, isPartial: false, resetCount: 6),
            CycleUtilization(label: "Feb", year: 2026, utilizationPercent: 20, dollarValue: 4, isPartial: true, resetCount: 2),
        ],
        timeRange: .month
    )
    .padding()
    .frame(width: 500)
}

#Preview("Stable — no dollar values") {
    CycleOverCycleBar(
        cycles: [
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 50, dollarValue: nil, isPartial: false, resetCount: 8),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 48, dollarValue: nil, isPartial: false, resetCount: 7),
            CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 52, dollarValue: nil, isPartial: false, resetCount: 9),
            CycleUtilization(label: "Jan", year: 2026, utilizationPercent: 49, dollarValue: nil, isPartial: false, resetCount: 8),
            CycleUtilization(label: "Feb", year: 2026, utilizationPercent: 30, dollarValue: nil, isPartial: true, resetCount: 3),
        ],
        timeRange: .all
    )
    .padding()
    .frame(width: 500)
}

#Preview("Hidden — .week time range") {
    VStack {
        Text("Bar should be hidden below (wrong time range):")
            .font(.caption)
        CycleOverCycleBar(
            cycles: [
                CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 50, dollarValue: 10, isPartial: false, resetCount: 8),
                CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 60, dollarValue: 12, isPartial: false, resetCount: 10),
                CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 70, dollarValue: 14, isPartial: false, resetCount: 12),
            ],
            timeRange: .week
        )
        Text("Nothing should appear above this line")
            .font(.caption)
    }
    .padding()
    .frame(width: 500)
}

#Preview("Hidden — insufficient data") {
    VStack {
        Text("Bar should be hidden below (< 3 cycles):")
            .font(.caption)
        CycleOverCycleBar(
            cycles: [
                CycleUtilization(label: "Jan", year: 2026, utilizationPercent: 60, dollarValue: 12, isPartial: false, resetCount: 10),
                CycleUtilization(label: "Feb", year: 2026, utilizationPercent: 40, dollarValue: 8, isPartial: true, resetCount: 4),
            ],
            timeRange: .all
        )
        Text("Nothing should appear above this line")
            .font(.caption)
    }
    .padding()
    .frame(width: 500)
}
#endif
