import Foundation
import os

/// Passive TPP measurement engine that correlates Claude Code log token data
/// with utilization poll changes to compute tokens-per-percent measurements.
///
/// Thread safety: uses NSLock to protect mutable accumulation window state,
/// following the same `@unchecked Sendable` pattern as `DatabaseManager`.
final class PassiveTPPEngine: PassiveTPPEngineProtocol, @unchecked Sendable {
    private let logParser: any ClaudeCodeLogParserProtocol
    private let tppStorage: any TPPStorageServiceProtocol
    private let lock = NSLock()

    // MARK: - Accumulation Window State (protected by lock)

    private var accumulationWindow: AccumulationWindow?

    // MARK: - Health Tracking (protected by lock)

    private var totalUtilizationChanges: Int = 0
    private var windowsWithTokenData: Int = 0

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "passive-tpp"
    )

    /// Maximum accumulation window duration (6 hours in milliseconds).
    private static let maxAccumulationMs: Int64 = 6 * 60 * 60 * 1000

    /// Minimum weekly utilization delta to trigger a TPP measurement.
    private static let minDelta: Double = 1.0

    /// Minimum weekly delta for medium confidence (single model).
    private static let mediumConfidenceDelta: Double = 2.0

    init(logParser: any ClaudeCodeLogParserProtocol, tppStorage: any TPPStorageServiceProtocol) {
        self.logParser = logParser
        self.tppStorage = tppStorage
    }

    func processPoll(current: UsagePoll, previous: UsagePoll) async {
        guard let currentSevenDay = current.sevenDayUtil,
              let previousSevenDay = previous.sevenDayUtil else {
            Self.logger.debug("Skipping passive TPP: missing 7d utilization data — discarding accumulation")
            lock.withLock { accumulationWindow = nil }
            return
        }

        // Weekly utilization only falls at a reset
        if currentSevenDay < previousSevenDay {
            Self.logger.info("Weekly reset detected: 7d dropped from \(previousSevenDay) to \(currentSevenDay) — discarding accumulation")
            lock.withLock { accumulationWindow = nil }
            return
        }

        let windowStartSevenDay = lock.withLock { accumulationWindow?.startSevenDayUtil }
        let cumulativeDelta = currentSevenDay - (windowStartSevenDay ?? previousSevenDay)

        // Query log parser for tokens in [previous.timestamp, current.timestamp)
        let tokenAggregates = logParser.getTokens(from: previous.timestamp, to: current.timestamp)
        let totalTokensAcrossModels = tokenAggregates.reduce(0) {
            $0 + $1.inputTokens + $1.outputTokens + $1.cacheCreateTokens + $1.cacheReadTokens
        }

        if cumulativeDelta >= Self.minDelta {
            lock.withLock { totalUtilizationChanges += 1 }

            let window = lock.withLock { () -> AccumulationWindow? in
                let w = accumulationWindow
                accumulationWindow = nil
                return w
            }

            var tokensByModel = window?.tokensByModel ?? [:]
            for aggregate in tokenAggregates {
                tokensByModel[aggregate.model] = Self.merge(tokensByModel[aggregate.model], aggregate)
            }
            let totalTokens = tokensByModel.values.reduce(0) {
                $0 + $1.inputTokens + $1.outputTokens + $1.cacheCreateTokens + $1.cacheReadTokens
            }

            let sevenDayBefore = window?.startSevenDayUtil ?? previousSevenDay
            let windowStart = window?.startTimestamp ?? previous.timestamp
            let windowDelta = currentSevenDay - sevenDayBefore
            Self.logger.debug("Weekly delta \(windowDelta) since \(windowStart) (accumulated=\(window != nil)) — tokens=\(totalTokens)")

            if totalTokens > 0 {
                lock.withLock { windowsWithTokenData += 1 }
                await storePerModelMeasurements(
                    tokensByModel: tokensByModel,
                    sevenDayBefore: sevenDayBefore,
                    sevenDayAfter: currentSevenDay,
                    sevenDayDelta: windowDelta,
                    windowStart: windowStart,
                    timestamp: current.timestamp
                )
            } else {
                // Delta with no tokens — non-Claude-Code usage
                await storeDeltaOnlyRecord(
                    sevenDayBefore: sevenDayBefore,
                    sevenDayAfter: currentSevenDay,
                    sevenDayDelta: windowDelta,
                    windowStart: windowStart,
                    timestamp: current.timestamp
                )
            }
        } else if totalTokensAcrossModels > 0 {
            // No meaningful delta but tokens consumed — accumulate
            enum AccumulationAction { case capExceeded, accumulated, started }
            let action: AccumulationAction = lock.withLock {
                if var window = accumulationWindow {
                    if current.timestamp - window.startTimestamp > Self.maxAccumulationMs {
                        var tokensByModel: [String: TokenAggregate] = [:]
                        for aggregate in tokenAggregates {
                            tokensByModel[aggregate.model] = aggregate
                        }
                        accumulationWindow = AccumulationWindow(
                            startTimestamp: previous.timestamp,
                            startSevenDayUtil: previousSevenDay,
                            tokensByModel: tokensByModel,
                            lastPollTimestamp: current.timestamp
                        )
                        return .capExceeded
                    }

                    for aggregate in tokenAggregates {
                        window.tokensByModel[aggregate.model] = Self.merge(window.tokensByModel[aggregate.model], aggregate)
                    }
                    window.lastPollTimestamp = current.timestamp
                    accumulationWindow = window
                    return .accumulated
                } else {
                    var tokensByModel: [String: TokenAggregate] = [:]
                    for aggregate in tokenAggregates {
                        tokensByModel[aggregate.model] = aggregate
                    }
                    accumulationWindow = AccumulationWindow(
                        startTimestamp: previous.timestamp,
                        startSevenDayUtil: previousSevenDay,
                        tokensByModel: tokensByModel,
                        lastPollTimestamp: current.timestamp
                    )
                    return .started
                }
            }
            switch action {
            case .capExceeded:
                Self.logger.info("Accumulation window exceeded 6h cap — discarding and restarting at \(previous.timestamp)")
            case .accumulated, .started:
                Self.logger.debug("Tokens accumulated — no weekly utilization delta yet (7d=\(currentSevenDay))")
            }
        }
        // If no delta AND no tokens, nothing to do
    }

    func getHealth() async -> PassiveTPPHealth {
        let (total, withData) = lock.withLock {
            (totalUtilizationChanges, windowsWithTokenData)
        }
        let coverage = total > 0 ? Double(withData) / Double(total) * 100.0 : 100.0
        let isDegraded = total > 0 && coverage < PassiveTPPHealth.degradationThreshold
        let suggestion: String? = isDegraded
            ? "Only \(Int(coverage))% of utilization changes had matching token data. Use the Measure button for more reliable readings."
            : nil

        return PassiveTPPHealth(
            totalUtilizationChanges: total,
            windowsWithTokenData: withData,
            coveragePercent: coverage,
            isDegraded: isDegraded,
            degradationSuggestion: suggestion
        )
    }

    func resetAccumulation() async {
        lock.withLock { accumulationWindow = nil }
        Self.logger.info("Accumulation window reset")
    }

    // MARK: - Private Helpers

    private static func merge(_ existing: TokenAggregate?, _ aggregate: TokenAggregate) -> TokenAggregate {
        guard var merged = existing else { return aggregate }
        merged.inputTokens += aggregate.inputTokens
        merged.outputTokens += aggregate.outputTokens
        merged.cacheCreateTokens += aggregate.cacheCreateTokens
        merged.cacheReadTokens += aggregate.cacheReadTokens
        merged.messageCount += aggregate.messageCount
        return merged
    }

    private func storePerModelMeasurements(
        tokensByModel: [String: TokenAggregate],
        sevenDayBefore: Double,
        sevenDayAfter: Double,
        sevenDayDelta: Double,
        windowStart: Int64,
        timestamp: Int64
    ) async {
        let isMultiModel = tokensByModel.count > 1

        for (_, aggregate) in tokensByModel {
            let totalRaw = aggregate.inputTokens + aggregate.outputTokens + aggregate.cacheCreateTokens + aggregate.cacheReadTokens
            // cache_read is free; cache_create costs 1.25x base input
            let effectiveTokens = Double(aggregate.inputTokens + aggregate.outputTokens) + Double(aggregate.cacheCreateTokens) * 1.25
            let tppSevenDay = effectiveTokens / sevenDayDelta

            let confidence: MeasurementConfidence =
                !isMultiModel && sevenDayDelta >= Self.mediumConfidenceDelta ? .medium : .low

            let measurement = TPPMeasurement(
                id: nil,
                timestamp: timestamp,
                windowStart: windowStart,
                model: aggregate.model,
                variant: nil,
                source: .passive,
                fiveHourBefore: nil,
                fiveHourAfter: nil,
                fiveHourDelta: nil,
                sevenDayBefore: sevenDayBefore,
                sevenDayAfter: sevenDayAfter,
                sevenDayDelta: sevenDayDelta,
                inputTokens: aggregate.inputTokens,
                outputTokens: aggregate.outputTokens,
                cacheCreateTokens: aggregate.cacheCreateTokens,
                cacheReadTokens: aggregate.cacheReadTokens,
                totalRawTokens: totalRaw,
                tppFiveHour: nil,
                tppSevenDay: tppSevenDay,
                confidence: confidence,
                messageCount: aggregate.messageCount
            )

            do {
                try await tppStorage.storePassiveResult(measurement)
                Self.logger.info("Stored passive TPP: model=\(aggregate.model, privacy: .public) tpp7d=\(tppSevenDay) delta7d=\(sevenDayDelta) confidence=\(confidence.rawValue, privacy: .public)")
            } catch {
                Self.logger.error("Failed to store passive TPP measurement: \(error.localizedDescription)")
            }
        }
    }

    private func storeDeltaOnlyRecord(
        sevenDayBefore: Double,
        sevenDayAfter: Double,
        sevenDayDelta: Double,
        windowStart: Int64,
        timestamp: Int64
    ) async {
        let measurement = TPPMeasurement(
            id: nil,
            timestamp: timestamp,
            windowStart: windowStart,
            model: "unknown",
            variant: nil,
            source: .passive,
            fiveHourBefore: nil,
            fiveHourAfter: nil,
            fiveHourDelta: nil,
            sevenDayBefore: sevenDayBefore,
            sevenDayAfter: sevenDayAfter,
            sevenDayDelta: sevenDayDelta,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreateTokens: 0,
            cacheReadTokens: 0,
            totalRawTokens: 0,
            tppFiveHour: nil,
            tppSevenDay: nil,
            confidence: .low,
            messageCount: 0
        )

        do {
            try await tppStorage.storePassiveResult(measurement)
            Self.logger.info("Stored delta-only record (non-Claude-Code usage): 7d delta=\(sevenDayDelta)")
        } catch {
            Self.logger.error("Failed to store delta-only TPP record: \(error.localizedDescription)")
        }
    }
}

// MARK: - Accumulation Window

extension PassiveTPPEngine {
    struct AccumulationWindow {
        let startTimestamp: Int64
        let startSevenDayUtil: Double
        var tokensByModel: [String: TokenAggregate]
        var lastPollTimestamp: Int64
    }
}
