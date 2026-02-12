import Foundation

/// Pure computation of per-cycle utilization for the cycle-over-cycle visualization.
/// Groups reset events by billing cycle (if billingCycleDay set) or calendar month,
/// computes utilization per group, and returns chronologically sorted results.
enum CycleUtilizationCalculator {

    private static let monthAbbreviations: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        return calendar.shortMonthSymbols
    }()

    /// Computes per-cycle utilization from reset events.
    ///
    /// - Parameters:
    ///   - resetEvents: All reset events (typically from `.all` time range)
    ///   - creditLimits: Credit limits for the user's tier (nil → percentage-only mode)
    ///   - billingCycleDay: User-configured billing day (1-28), nil for calendar month grouping
    ///   - headroomAnalysisService: Service for computing aggregate breakdowns
    /// - Returns: Chronologically sorted array of per-cycle utilization; empty if fewer than 3 complete cycles
    static func computeCycles(
        resetEvents: [ResetEvent],
        creditLimits: CreditLimits?,
        billingCycleDay: Int?,
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol
    ) -> [CycleUtilization] {
        guard !resetEvents.isEmpty else { return [] }

        let groups: [(key: CycleKey, events: [ResetEvent])]
        if let day = billingCycleDay {
            groups = groupByBillingCycle(events: resetEvents, billingDay: day)
        } else {
            groups = groupByCalendarMonth(events: resetEvents)
        }

        guard !groups.isEmpty else { return [] }

        let now = Date()
        let calendar = Calendar.current

        var cycles: [CycleUtilization] = []
        for (index, group) in groups.enumerated() {
            let isLast = index == groups.count - 1
            let isPartial = isLast && isCycleInProgress(key: group.key, billingCycleDay: billingCycleDay, now: now, calendar: calendar)

            let utilization: Double
            var dollarValue: Double?

            if let limits = creditLimits,
               let value = SubscriptionValueCalculator.calculate(
                   resetEvents: group.events,
                   creditLimits: limits,
                   timeRange: .month,
                   headroomAnalysisService: headroomAnalysisService
               ) {
                utilization = value.utilizationPercent
                dollarValue = value.usedDollars
            } else {
                // Percentage-only fallback
                let summary = headroomAnalysisService.aggregateBreakdown(events: group.events)
                utilization = summary.usedPercent
            }

            cycles.append(CycleUtilization(
                label: group.key.label,
                year: group.key.year,
                utilizationPercent: utilization,
                dollarValue: dollarValue,
                isPartial: isPartial,
                resetCount: group.events.count
            ))
        }

        // Require at least 3 complete cycles (partial doesn't count)
        let completeCount = cycles.filter { !$0.isPartial }.count
        guard completeCount >= 3 else { return [] }

        return cycles
    }

    // MARK: - Grouping

    /// Groups events by calendar month (year + month).
    private static func groupByCalendarMonth(events: [ResetEvent]) -> [(key: CycleKey, events: [ResetEvent])] {
        let calendar = Calendar.current
        var groups: [CycleKey: [ResetEvent]] = [:]

        for event in events {
            let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000.0)
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else { continue }
            let key = CycleKey(year: year, month: month, label: monthAbbreviations[month - 1])
            groups[key, default: []].append(event)
        }

        return groups.sorted { $0.key < $1.key }.map { (key: $0.key, events: $0.value) }
    }

    /// Groups events by billing cycle boundaries.
    /// Cycle "Jan 2026" starts on Jan `billingDay` and ends on Feb `billingDay - 1`.
    private static func groupByBillingCycle(events: [ResetEvent], billingDay: Int) -> [(key: CycleKey, events: [ResetEvent])] {
        let calendar = Calendar.current
        var groups: [CycleKey: [ResetEvent]] = [:]

        for event in events {
            let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000.0)
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day else { continue }

            // If the event day is before the billing day, it belongs to the previous billing cycle
            let cycleYear: Int
            let cycleMonth: Int
            if day < billingDay {
                if month == 1 {
                    cycleYear = year - 1
                    cycleMonth = 12
                } else {
                    cycleYear = year
                    cycleMonth = month - 1
                }
            } else {
                cycleYear = year
                cycleMonth = month
            }

            let key = CycleKey(year: cycleYear, month: cycleMonth, label: monthAbbreviations[cycleMonth - 1])
            groups[key, default: []].append(event)
        }

        return groups.sorted { $0.key < $1.key }.map { (key: $0.key, events: $0.value) }
    }

    // MARK: - Partial Cycle Detection

    /// Determines if a cycle is currently in progress (not yet ended).
    private static func isCycleInProgress(key: CycleKey, billingCycleDay: Int?, now: Date, calendar: Calendar) -> Bool {
        let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)
        guard let nowYear = nowComponents.year, let nowMonth = nowComponents.month, let nowDay = nowComponents.day else { return false }

        if let billingDay = billingCycleDay {
            // Current billing cycle: the cycle whose start date <= now < next cycle start
            let currentCycleYear: Int
            let currentCycleMonth: Int
            if nowDay < billingDay {
                if nowMonth == 1 {
                    currentCycleYear = nowYear - 1
                    currentCycleMonth = 12
                } else {
                    currentCycleYear = nowYear
                    currentCycleMonth = nowMonth - 1
                }
            } else {
                currentCycleYear = nowYear
                currentCycleMonth = nowMonth
            }
            return key.year == currentCycleYear && key.month == currentCycleMonth
        } else {
            // Calendar month: partial if same year+month as now
            return key.year == nowYear && key.month == nowMonth
        }
    }
}

// MARK: - CycleKey

/// Internal key for grouping events into cycles.
struct CycleKey: Hashable, Comparable {
    let year: Int
    let month: Int
    let label: String

    static func < (lhs: CycleKey, rhs: CycleKey) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
    }
}
