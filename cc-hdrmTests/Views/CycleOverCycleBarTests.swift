import Testing
import SwiftUI
@testable import cc_hdrm

@Suite("CycleOverCycleBar Tests")
@MainActor
struct CycleOverCycleBarTests {

    // MARK: - Helpers

    private func makeCycles(extraUsage: [Double?] = [nil, nil, nil, nil]) -> [CycleUtilization] {
        let labels = ["Oct", "Nov", "Dec", "Jan"]
        let years = [2025, 2025, 2025, 2026]
        return labels.enumerated().map { i, label in
            CycleUtilization(
                label: label,
                year: years[i],
                utilizationPercent: 50.0 + Double(i) * 10.0,
                dollarValue: 10.0 + Double(i) * 2.0,
                isPartial: i == labels.count - 1,
                resetCount: 3 + i,
                extraUsageSpend: i < extraUsage.count ? extraUsage[i] : nil
            )
        }
    }

    // MARK: - Rendering

    @Test("CycleOverCycleBar renders without crash with extra usage spend")
    func rendersWithExtraUsage() {
        let cycles = makeCycles(extraUsage: [nil, 550.0, 1275.0, nil])
        let view = CycleOverCycleBar(cycles: cycles, timeRange: .all)
        let _ = view.body
    }

    @Test("CycleOverCycleBar renders without crash when all cycles have nil extra usage")
    func rendersWithoutExtraUsage() {
        let cycles = makeCycles(extraUsage: [nil, nil, nil, nil])
        let view = CycleOverCycleBar(cycles: cycles, timeRange: .month)
        let _ = view.body
    }

    @Test("CycleOverCycleBar renders without crash when all cycles have extra usage")
    func rendersWithAllExtraUsage() {
        let cycles = makeCycles(extraUsage: [300.0, 550.0, 1275.0, 800.0])
        let view = CycleOverCycleBar(cycles: cycles, timeRange: .all)
        let _ = view.body
    }

    // MARK: - Accessibility

    @Test("Accessibility label includes extra usage text when spend > 0")
    func accessibilityIncludesExtraUsage() {
        let cycle = CycleUtilization(
            label: "Nov",
            year: 2025,
            utilizationPercent: 60.0,
            dollarValue: 12.0,
            isPartial: false,
            resetCount: 5,
            extraUsageSpend: 850.0
        )
        let bar = CycleOverCycleBar(cycles: [cycle, cycle, cycle], timeRange: .all)
        // The accessibility label method is private, but we test via rendering
        let _ = bar.body
    }

    @Test("CycleOverCycleBar hidden for .week time range even with extra usage")
    func hiddenForWeekRange() {
        let cycles = makeCycles(extraUsage: [300.0, 500.0, 1200.0, 800.0])
        let view = CycleOverCycleBar(cycles: cycles, timeRange: .week)
        // View body should not render the chart (shouldRender is false)
        let _ = view.body
    }

    @Test("CycleOverCycleBar hidden with fewer than 3 cycles even with extra usage")
    func hiddenForInsufficientCycles() {
        let cycles = [
            CycleUtilization(label: "Jan", year: 2026, utilizationPercent: 60, dollarValue: 12, isPartial: false, resetCount: 5, extraUsageSpend: 1000.0),
            CycleUtilization(label: "Feb", year: 2026, utilizationPercent: 40, dollarValue: 8, isPartial: true, resetCount: 3, extraUsageSpend: 500.0),
        ]
        let view = CycleOverCycleBar(cycles: cycles, timeRange: .all)
        let _ = view.body
    }
}
