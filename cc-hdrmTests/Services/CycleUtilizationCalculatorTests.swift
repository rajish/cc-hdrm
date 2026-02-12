import Foundation
import Testing
@testable import cc_hdrm

@Suite("CycleUtilizationCalculator Tests")
struct CycleUtilizationCalculatorTests {

    // MARK: - Helpers

    private let proLimits = RateLimitTier.pro.creditLimits

    private func makeMockService(
        usedPercent: Double = 52
    ) -> MockHeadroomAnalysisService {
        let mock = MockHeadroomAnalysisService()
        mock.mockPeriodSummary = PeriodSummary(
            usedCredits: 2_860_000,
            constrainedCredits: 660_000,
            unusedCredits: 1_980_000,
            resetCount: 3,
            avgPeakUtilization: usedPercent,
            usedPercent: usedPercent,
            constrainedPercent: 12,
            unusedPercent: 36
        )
        return mock
    }

    /// Creates events spanning multiple months with configurable per-month event counts.
    /// Events are placed 2 days apart within each month to ensure they group correctly.
    private func makeMonthlyEvents(monthsBack: Int, eventsPerMonth: Int = 3) -> [ResetEvent] {
        let calendar = Calendar.current
        var events: [ResetEvent] = []
        var id: Int64 = 1

        for monthOffset in (0..<monthsBack).reversed() {
            guard let monthStart = calendar.date(byAdding: .month, value: -monthOffset, to: Date()),
                  let startOfMonth = calendar.dateInterval(of: .month, for: monthStart)?.start else { continue }

            for dayOffset in 0..<eventsPerMonth {
                guard let eventDate = calendar.date(byAdding: .day, value: dayOffset * 2 + 1, to: startOfMonth) else { continue }
                let ts = Int64(eventDate.timeIntervalSince1970 * 1000)
                events.append(ResetEvent(
                    id: id,
                    timestamp: ts,
                    fiveHourPeak: 50.0 + Double(monthOffset),
                    sevenDayUtil: 40.0 + Double(monthOffset),
                    tier: "default_claude_pro",
                    usedCredits: nil,
                    constrainedCredits: nil,
                    unusedCredits: nil
                ))
                id += 1
            }
        }

        return events.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - 8.2: Calendar month grouping

    @Test("Groups events by calendar month with correct labels")
    func calendarMonthGrouping() {
        let mock = makeMockService()
        let events = makeMonthlyEvents(monthsBack: 5)

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: events,
            creditLimits: proLimits,
            billingCycleDay: nil,
            headroomAnalysisService: mock
        )

        // 5 months back: current month is partial → 4 complete + 1 partial
        // Need 3+ complete → should produce results
        #expect(cycles.count >= 4)

        // Labels should be 3-letter month abbreviations
        let validLabels = Calendar.current.shortMonthSymbols
        for cycle in cycles {
            #expect(validLabels.contains(cycle.label))
        }

        // Should be chronologically sorted
        for i in 1..<cycles.count {
            let prev = cycles[i - 1]
            let curr = cycles[i]
            let prevKey = prev.year * 100 + (Calendar.current.shortMonthSymbols.firstIndex(of: prev.label)! + 1)
            let currKey = curr.year * 100 + (Calendar.current.shortMonthSymbols.firstIndex(of: curr.label)! + 1)
            #expect(prevKey < currKey)
        }
    }

    // MARK: - 8.3: Billing cycle grouping

    @Test("Groups events by billing cycle boundaries when billingCycleDay is set")
    func billingCycleGrouping() {
        let mock = makeMockService()
        let calendar = Calendar.current

        // Create events around billing day 15
        var events: [ResetEvent] = []
        var id: Int64 = 1

        // Create events for 5 billing cycles
        for monthOffset in (0..<5).reversed() {
            guard let monthDate = calendar.date(byAdding: .month, value: -monthOffset, to: Date()),
                  let startOfMonth = calendar.dateInterval(of: .month, for: monthDate)?.start else { continue }

            // Events on day 16, 20, 25 — after billing day 15 → belong to this billing cycle
            for dayOffset in [16, 20, 25] {
                guard let eventDate = calendar.date(byAdding: .day, value: dayOffset - 1, to: startOfMonth) else { continue }
                let ts = Int64(eventDate.timeIntervalSince1970 * 1000)
                events.append(ResetEvent(
                    id: id,
                    timestamp: ts,
                    fiveHourPeak: 50.0,
                    sevenDayUtil: 40.0,
                    tier: "default_claude_pro",
                    usedCredits: nil,
                    constrainedCredits: nil,
                    unusedCredits: nil
                ))
                id += 1
            }
        }

        events.sort { $0.timestamp < $1.timestamp }

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: events,
            creditLimits: proLimits,
            billingCycleDay: 15,
            headroomAnalysisService: mock
        )

        // Should produce cycles (at least 3 complete required)
        #expect(cycles.count >= 3)
    }

    // MARK: - 8.4: Fewer than 3 complete cycles

    @Test("Returns empty array when fewer than 3 complete cycles exist")
    func fewerThanThreeCycles() {
        let mock = makeMockService()
        let events = makeMonthlyEvents(monthsBack: 2)

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: events,
            creditLimits: proLimits,
            billingCycleDay: nil,
            headroomAnalysisService: mock
        )

        // 2 months: current is partial → only 1 complete → should be empty
        #expect(cycles.isEmpty)
    }

    @Test("Returns empty for 2 complete + 1 partial cycles")
    func twoCompletePlusPartial() {
        let mock = makeMockService()
        // 3 months: current month is partial → 2 complete → not enough
        let events = makeMonthlyEvents(monthsBack: 3)

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: events,
            creditLimits: proLimits,
            billingCycleDay: nil,
            headroomAnalysisService: mock
        )

        #expect(cycles.isEmpty)
    }

    // MARK: - 8.5: Partial cycle detection

    @Test("Current partial cycle has isPartial true")
    func currentCycleIsPartial() {
        let mock = makeMockService()
        // 5 months → 4 complete + 1 partial (current)
        let events = makeMonthlyEvents(monthsBack: 5)

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: events,
            creditLimits: proLimits,
            billingCycleDay: nil,
            headroomAnalysisService: mock
        )

        #expect(!cycles.isEmpty)
        // Last cycle should be partial
        #expect(cycles.last?.isPartial == true)
        // All others should be complete
        for cycle in cycles.dropLast() {
            #expect(cycle.isPartial == false)
        }
    }

    // MARK: - 8.6: Utilization percentages

    @Test("Utilization percentages are populated for all cycles")
    func utilizationPercentagesPopulated() {
        let mock = makeMockService()
        let events = makeMonthlyEvents(monthsBack: 5)

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: events,
            creditLimits: proLimits,
            billingCycleDay: nil,
            headroomAnalysisService: mock
        )

        #expect(!cycles.isEmpty)
        for cycle in cycles {
            #expect(cycle.utilizationPercent >= 0)
            #expect(cycle.utilizationPercent <= 100)
        }
    }

    // MARK: - 8.7: Dollar values

    @Test("Dollar values populated when creditLimits has monthlyPrice")
    func dollarValuesPopulated() {
        let mock = makeMockService()
        let events = makeMonthlyEvents(monthsBack: 5)

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: events,
            creditLimits: proLimits,
            billingCycleDay: nil,
            headroomAnalysisService: mock
        )

        #expect(!cycles.isEmpty)
        for cycle in cycles {
            #expect(cycle.dollarValue != nil)
        }
    }

    @Test("Dollar values nil when creditLimits has no monthlyPrice")
    func dollarValuesNilWithoutMonthlyPrice() {
        let mock = makeMockService()
        let events = makeMonthlyEvents(monthsBack: 5)
        let customLimits = CreditLimits(fiveHourCredits: 550_000, sevenDayCredits: 5_000_000)

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: events,
            creditLimits: customLimits,
            billingCycleDay: nil,
            headroomAnalysisService: mock
        )

        #expect(!cycles.isEmpty)
        for cycle in cycles {
            #expect(cycle.dollarValue == nil)
        }
    }

    // MARK: - Edge cases

    @Test("Empty events returns empty array")
    func emptyEvents() {
        let mock = makeMockService()

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: [],
            creditLimits: proLimits,
            billingCycleDay: nil,
            headroomAnalysisService: mock
        )

        #expect(cycles.isEmpty)
    }

    @Test("Nil creditLimits uses percentage-only fallback")
    func nilCreditLimitsPercentageFallback() {
        let mock = makeMockService()
        let events = makeMonthlyEvents(monthsBack: 5)

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: events,
            creditLimits: nil,
            billingCycleDay: nil,
            headroomAnalysisService: mock
        )

        #expect(!cycles.isEmpty)
        for cycle in cycles {
            #expect(cycle.utilizationPercent >= 0)
            #expect(cycle.dollarValue == nil)
        }
    }

    @Test("CycleUtilization id combines year and label")
    func cycleUtilizationId() {
        let cycle = CycleUtilization(
            label: "Jan",
            year: 2026,
            utilizationPercent: 52.0,
            dollarValue: 10.0,
            isPartial: false,
            resetCount: 3
        )
        #expect(cycle.id == "2026-Jan")
    }

    // MARK: - Self-Benchmarking Anchors (Task 9)

    @Test("Peak detection returns insight when current exceeds historical peak")
    func peakDetection() {
        // Create cycles where current partial cycle exceeds all complete cycles
        let cycles = [
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 50.0, dollarValue: 10.0, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 60.0, dollarValue: 12.0, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 70.0, dollarValue: 14.0, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Jan", year: 2026, utilizationPercent: 85.0, dollarValue: 17.0, isPartial: true, resetCount: 2),
        ]

        let anchors = ValueInsightEngine.computeBenchmarkAnchors(cycles: cycles)

        let peakAnchor = anchors.first { $0.text.contains("heaviest") }
        #expect(peakAnchor != nil)
        #expect(peakAnchor?.priority == .usageDeviation)
        #expect(peakAnchor?.text.contains("since") == true)
    }

    @Test("Consecutive months above 80% detected")
    func consecutiveHighMonths() {
        let cycles = [
            CycleUtilization(label: "Sep", year: 2025, utilizationPercent: 50.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 85.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 88.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 92.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Jan", year: 2026, utilizationPercent: 90.0, dollarValue: nil, isPartial: true, resetCount: 2),
        ]

        let anchors = ValueInsightEngine.computeBenchmarkAnchors(cycles: cycles)

        let consecutiveAnchor = anchors.first { $0.text.contains("consecutive") }
        #expect(consecutiveAnchor != nil)
        #expect(consecutiveAnchor?.text.contains("80%") == true)
        #expect(consecutiveAnchor?.priority == .usageDeviation)
    }

    @Test("Decline from peak detected when current is significantly below")
    func declineFromPeak() {
        let cycles = [
            CycleUtilization(label: "Sep", year: 2025, utilizationPercent: 30.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 90.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 60.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 40.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Jan", year: 2026, utilizationPercent: 30.0, dollarValue: nil, isPartial: true, resetCount: 2),
        ]

        let anchors = ValueInsightEngine.computeBenchmarkAnchors(cycles: cycles)

        let declineAnchor = anchors.first { $0.text.contains("down") }
        #expect(declineAnchor != nil)
        #expect(declineAnchor?.text.contains("peak") == true)
        #expect(declineAnchor?.priority == .usageDeviation)
    }

    @Test("No anchors returned when insufficient history (< 3 complete cycles)")
    func noAnchorsInsufficientHistory() {
        let cycles = [
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 60.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 70.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Jan", year: 2026, utilizationPercent: 85.0, dollarValue: nil, isPartial: true, resetCount: 2),
        ]

        let anchors = ValueInsightEngine.computeBenchmarkAnchors(cycles: cycles)

        // Only 2 complete cycles → insufficient
        #expect(anchors.isEmpty)
    }

    @Test("No consecutive anchor when run is shorter than 3")
    func noConsecutiveWhenShortRun() {
        let cycles = [
            CycleUtilization(label: "Sep", year: 2025, utilizationPercent: 50.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 85.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 88.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 50.0, dollarValue: nil, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Jan", year: 2026, utilizationPercent: 60.0, dollarValue: nil, isPartial: true, resetCount: 2),
        ]

        let anchors = ValueInsightEngine.computeBenchmarkAnchors(cycles: cycles)

        let consecutiveAnchor = anchors.first { $0.text.contains("consecutive") }
        #expect(consecutiveAnchor == nil)
    }
}
