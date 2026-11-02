import Foundation
import os

/// Turns polls with no 5-hour number into TPP rows based on weekly steps.
/// Shared by the passive engine and the backfill so both apply one rule.
///
/// Weekly percents are whole numbers. A window holds all of a step's logged tokens only if it
/// follows an observed step with nothing lost since, so only such a window produces a TPP value.
struct WeeklyStepTracker {
    struct Outcome {
        var isStep = false
        var hadTokens = false
        var measurements: [TPPMeasurement] = []
    }

    private struct Window {
        let startTimestamp: Int64
        let startSevenDayUtil: Double
        let tokensByModel: [String: TokenAggregate]
    }

    /// ponytail: a 1% step spanning more than this never yields a value; raise it if light users see no readings.
    private static let maxWindowMs: Int64 = 6 * 60 * 60 * 1000
    private static let minDelta: Double = 1.0
    private static let mediumConfidenceDelta: Double = 3.0
    /// Smaller moves with no fall in usage are the reset time drifting, not a new cycle.
    private static let resetShiftMs: Int64 = 6 * 24 * 60 * 60 * 1000

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "weekly-tpp"
    )

    private let source: MeasurementSource
    private var window: Window?
    private var isAnchored = false

    init(source: MeasurementSource) {
        self.source = source
    }

    mutating func reset() {
        window = nil
        isAnchored = false
    }

    mutating func process(current: UsagePoll, previous: UsagePoll, tokens: [TokenAggregate]) -> Outcome {
        guard current.fiveHourUtil == nil, previous.fiveHourUtil == nil else {
            Self.logger.info("5-hour number present on one side of the pair (\(previous.timestamp) to \(current.timestamp)) — discarding weekly window")
            reset()
            return Outcome()
        }
        guard let currentUtil = current.sevenDayUtil, let previousUtil = previous.sevenDayUtil else {
            Self.logger.debug("Missing weekly utilization — discarding weekly window")
            reset()
            return Outcome()
        }
        if currentUtil < previousUtil || Self.resetTimeJumped(current: current, previous: previous) {
            Self.logger.info("Weekly reset between \(previous.timestamp) and \(current.timestamp) (\(previousUtil) to \(currentUtil)) — discarding weekly window")
            reset()
            return Outcome()
        }
        // A long gap with no step and no tokens loses nothing, so the anchor survives a night's sleep.
        let isEmptyGap = window == nil && currentUtil - previousUtil < Self.minDelta && !tokens.contains { Self.rawTokens($0) > 0 }
        if !isEmptyGap, current.timestamp - (window?.startTimestamp ?? previous.timestamp) > Self.maxWindowMs {
            Self.logger.info("Weekly window older than 6 hours at \(current.timestamp) — discarding")
            reset()
        }

        let startTimestamp = window?.startTimestamp ?? previous.timestamp
        let startUtil = window?.startSevenDayUtil ?? previousUtil
        let delta = currentUtil - startUtil
        var tokensByModel = window?.tokensByModel ?? [:]
        for aggregate in tokens {
            tokensByModel[aggregate.model] = Self.merge(tokensByModel[aggregate.model], aggregate)
        }

        guard delta >= Self.minDelta else {
            if tokens.contains(where: { Self.rawTokens($0) > 0 }) {
                window = Window(startTimestamp: startTimestamp, startSevenDayUtil: startUtil, tokensByModel: tokensByModel)
            }
            return Outcome()
        }

        let wasAnchored = isAnchored
        window = nil
        isAnchored = true

        func row(model: String, aggregate: TokenAggregate?, confidence: MeasurementConfidence) -> TPPMeasurement {
            let effective = aggregate.map { Double($0.inputTokens + $0.outputTokens) + Double($0.cacheCreateTokens) * 1.25 } ?? 0
            return TPPMeasurement(
                id: nil,
                timestamp: current.timestamp,
                windowStart: startTimestamp,
                model: model,
                variant: nil,
                source: source,
                fiveHourBefore: nil,
                fiveHourAfter: nil,
                fiveHourDelta: nil,
                sevenDayBefore: startUtil,
                sevenDayAfter: currentUtil,
                sevenDayDelta: delta,
                inputTokens: aggregate?.inputTokens ?? 0,
                outputTokens: aggregate?.outputTokens ?? 0,
                cacheCreateTokens: aggregate?.cacheCreateTokens ?? 0,
                cacheReadTokens: aggregate?.cacheReadTokens ?? 0,
                totalRawTokens: aggregate.map(Self.rawTokens) ?? 0,
                tppFiveHour: nil,
                tppSevenDay: effective > 0 ? effective / delta : nil,
                confidence: confidence,
                messageCount: aggregate?.messageCount ?? 0
            )
        }

        let aggregates = tokensByModel.values
            .filter { Self.rawTokens($0) > 0 }
            .sorted { $0.model < $1.model }
        guard !aggregates.isEmpty else {
            Self.logger.info("Weekly step +\(delta) with no tokens — storing delta-only row")
            return Outcome(isStep: true, measurements: [row(model: "unknown", aggregate: nil, confidence: .low)])
        }
        guard wasAnchored else {
            Self.logger.info("Weekly step +\(delta) at \(current.timestamp) closes a partial window — anchoring here, storing no value")
            return Outcome(isStep: true, hadTokens: true)
        }

        let confidence: MeasurementConfidence = aggregates.count == 1 && delta >= Self.mediumConfidenceDelta ? .medium : .low
        return Outcome(
            isStep: true,
            hadTokens: true,
            measurements: aggregates.map { row(model: $0.model, aggregate: $0, confidence: confidence) }
        )
    }

    private static func resetTimeJumped(current: UsagePoll, previous: UsagePoll) -> Bool {
        guard let currentResetsAt = current.sevenDayResetsAt, let previousResetsAt = previous.sevenDayResetsAt else {
            return false
        }
        return currentResetsAt - previousResetsAt >= resetShiftMs
    }

    private static func rawTokens(_ aggregate: TokenAggregate) -> Int {
        aggregate.inputTokens + aggregate.outputTokens + aggregate.cacheCreateTokens + aggregate.cacheReadTokens
    }

    private static func merge(_ existing: TokenAggregate?, _ aggregate: TokenAggregate) -> TokenAggregate {
        guard var merged = existing else { return aggregate }
        merged.inputTokens += aggregate.inputTokens
        merged.outputTokens += aggregate.outputTokens
        merged.cacheCreateTokens += aggregate.cacheCreateTokens
        merged.cacheReadTokens += aggregate.cacheReadTokens
        merged.messageCount += aggregate.messageCount
        return merged
    }
}
