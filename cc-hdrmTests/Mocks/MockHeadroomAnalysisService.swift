import Foundation
@testable import cc_hdrm

/// Mock for HeadroomAnalysisService with configurable return values and call tracking.
/// Set `mockBreakdown` / `mockPeriodSummary` before calling; unconfigured calls fatalError.
final class MockHeadroomAnalysisService: HeadroomAnalysisServiceProtocol, @unchecked Sendable {
    var analyzeResetEventCallCount = 0
    var aggregateBreakdownCallCount = 0
    var lastFiveHourPeak: Double?
    var lastSevenDayUtil: Double?
    var lastCreditLimits: CreditLimits?
    var lastEvents: [ResetEvent]?

    /// Configurable return value for analyzeResetEvent. Must be set before calling.
    var mockBreakdown: HeadroomBreakdown?

    /// Configurable return value for aggregateBreakdown. Must be set before calling.
    var mockPeriodSummary: PeriodSummary?

    /// Optional closure for dynamic responses based on events.
    /// Takes precedence over `mockPeriodSummary` when set.
    var aggregateBreakdownHandler: (([ResetEvent]) -> PeriodSummary)?

    func analyzeResetEvent(
        fiveHourPeak: Double,
        sevenDayUtil: Double,
        creditLimits: CreditLimits
    ) -> HeadroomBreakdown {
        analyzeResetEventCallCount += 1
        lastFiveHourPeak = fiveHourPeak
        lastSevenDayUtil = sevenDayUtil
        lastCreditLimits = creditLimits

        guard let mock = mockBreakdown else {
            fatalError("MockHeadroomAnalysisService.analyzeResetEvent called without setting mockBreakdown")
        }
        return mock
    }

    func aggregateBreakdown(
        events: [ResetEvent]
    ) -> PeriodSummary {
        aggregateBreakdownCallCount += 1
        lastEvents = events

        if let handler = aggregateBreakdownHandler {
            return handler(events)
        }

        guard let mock = mockPeriodSummary else {
            fatalError("MockHeadroomAnalysisService.aggregateBreakdown called without setting mockPeriodSummary or aggregateBreakdownHandler")
        }
        return mock
    }
}
