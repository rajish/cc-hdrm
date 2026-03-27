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

    /// Maximum accumulation window duration (30 minutes in milliseconds).
    private static let maxAccumulationMs: Int64 = 30 * 60 * 1000

    /// Minimum utilization delta to trigger a TPP measurement.
    private static let minDelta: Double = 1.0

    /// Utilization drop threshold for reset detection (50%).
    private static let resetDropThreshold: Double = 50.0

    /// Minimum 5h delta for medium confidence (single model).
    private static let mediumConfidenceDelta: Double = 3.0

    init(logParser: any ClaudeCodeLogParserProtocol, tppStorage: any TPPStorageServiceProtocol) {
        self.logParser = logParser
        self.tppStorage = tppStorage
    }

    func processPoll(current: UsagePoll, previous: UsagePoll) async {
        guard let currentFiveHour = current.fiveHourUtil,
              let previousFiveHour = previous.fiveHourUtil else {
            Self.logger.debug("Skipping passive TPP: missing 5h utilization data")
            return
        }

        // Reset detection: 5h utilization drops by >= 50%
        if previousFiveHour - currentFiveHour >= Self.resetDropThreshold {
            Self.logger.info("Reset detected: 5h dropped from \(previousFiveHour) to \(currentFiveHour) — discarding accumulation")
            lock.withLock { accumulationWindow = nil }
            return
        }

        let fiveHourDelta = currentFiveHour - previousFiveHour
        let sevenDayDelta: Double? = {
            guard let curr = current.sevenDayUtil, let prev = previous.sevenDayUtil else { return nil }
            return curr - prev
        }()

        // Query log parser for tokens in [previous.timestamp, current.timestamp)
        let tokenAggregates = logParser.getTokens(from: previous.timestamp, to: current.timestamp)
        let totalTokensAcrossModels = tokenAggregates.reduce(0) {
            $0 + $1.inputTokens + $1.outputTokens + $1.cacheCreateTokens + $1.cacheReadTokens
        }

        let hasDelta = fiveHourDelta >= Self.minDelta || (sevenDayDelta ?? 0) >= Self.minDelta

        if hasDelta {
            // We have a meaningful utilization change — process it
            lock.withLock { totalUtilizationChanges += 1 }

            // Check if we have an accumulation window to flush
            let window = lock.withLock { () -> AccumulationWindow? in
                let w = accumulationWindow
                accumulationWindow = nil
                return w
            }

            if let window = window {
                // Flush accumulated window + current poll tokens
                var mergedTokens = window.tokensByModel
                for aggregate in tokenAggregates {
                    if var existing = mergedTokens[aggregate.model] {
                        existing.inputTokens += aggregate.inputTokens
                        existing.outputTokens += aggregate.outputTokens
                        existing.cacheCreateTokens += aggregate.cacheCreateTokens
                        existing.cacheReadTokens += aggregate.cacheReadTokens
                        existing.messageCount += aggregate.messageCount
                        mergedTokens[aggregate.model] = existing
                    } else {
                        mergedTokens[aggregate.model] = aggregate
                    }
                }

                let totalMerged = mergedTokens.values.reduce(0) {
                    $0 + $1.inputTokens + $1.outputTokens + $1.cacheCreateTokens + $1.cacheReadTokens
                }

                // Compute delta from window start to current poll
                let windowFiveHourDelta = currentFiveHour - window.startFiveHourUtil
                let windowSevenDayDelta: Double? = {
                    guard let startSD = window.startSevenDayUtil, let currSD = current.sevenDayUtil else { return nil }
                    return currSD - startSD
                }()

                if totalMerged > 0 {
                    lock.withLock { windowsWithTokenData += 1 }
                    await storePerModelMeasurements(
                        tokensByModel: mergedTokens,
                        fiveHourBefore: window.startFiveHourUtil,
                        fiveHourAfter: currentFiveHour,
                        fiveHourDelta: windowFiveHourDelta,
                        sevenDayBefore: window.startSevenDayUtil,
                        sevenDayAfter: current.sevenDayUtil,
                        sevenDayDelta: windowSevenDayDelta,
                        windowStart: window.startTimestamp,
                        timestamp: current.timestamp
                    )
                } else {
                    // Delta with no tokens — non-Claude-Code usage
                    await storeDeltaOnlyRecord(
                        fiveHourBefore: window.startFiveHourUtil,
                        fiveHourAfter: currentFiveHour,
                        fiveHourDelta: windowFiveHourDelta,
                        sevenDayBefore: window.startSevenDayUtil,
                        sevenDayAfter: current.sevenDayUtil,
                        sevenDayDelta: windowSevenDayDelta,
                        windowStart: window.startTimestamp,
                        timestamp: current.timestamp
                    )
                }
            } else {
                // No accumulation window — use direct poll-to-poll data
                if totalTokensAcrossModels > 0 {
                    lock.withLock { windowsWithTokenData += 1 }
                    var tokensByModel: [String: TokenAggregate] = [:]
                    for aggregate in tokenAggregates {
                        tokensByModel[aggregate.model] = aggregate
                    }
                    await storePerModelMeasurements(
                        tokensByModel: tokensByModel,
                        fiveHourBefore: previousFiveHour,
                        fiveHourAfter: currentFiveHour,
                        fiveHourDelta: fiveHourDelta,
                        sevenDayBefore: previous.sevenDayUtil,
                        sevenDayAfter: current.sevenDayUtil,
                        sevenDayDelta: sevenDayDelta,
                        windowStart: previous.timestamp,
                        timestamp: current.timestamp
                    )
                } else {
                    // Delta with no tokens — non-Claude-Code usage
                    await storeDeltaOnlyRecord(
                        fiveHourBefore: previousFiveHour,
                        fiveHourAfter: currentFiveHour,
                        fiveHourDelta: fiveHourDelta,
                        sevenDayBefore: previous.sevenDayUtil,
                        sevenDayAfter: current.sevenDayUtil,
                        sevenDayDelta: sevenDayDelta,
                        windowStart: previous.timestamp,
                        timestamp: current.timestamp
                    )
                }
            }
        } else if totalTokensAcrossModels > 0 {
            // No meaningful delta but tokens consumed — accumulate
            enum AccumulationAction { case capExceeded, monotonicViolation, accumulated, started }
            let action: AccumulationAction = lock.withLock {
                if var window = accumulationWindow {
                    // Check 30-minute cap
                    if current.timestamp - window.startTimestamp > Self.maxAccumulationMs {
                        accumulationWindow = AccumulationWindow(
                            startTimestamp: previous.timestamp,
                            startFiveHourUtil: previousFiveHour,
                            startSevenDayUtil: previous.sevenDayUtil,
                            tokensByModel: [:],
                            lastPollTimestamp: current.timestamp
                        )
                        // Add current tokens to the fresh window
                        for aggregate in tokenAggregates {
                            accumulationWindow?.tokensByModel[aggregate.model] = aggregate
                        }
                        return .capExceeded
                    }

                    // Monotonic guard: if utilization decreased during accumulation, discard
                    if currentFiveHour < window.startFiveHourUtil {
                        accumulationWindow = AccumulationWindow(
                            startTimestamp: previous.timestamp,
                            startFiveHourUtil: previousFiveHour,
                            startSevenDayUtil: previous.sevenDayUtil,
                            tokensByModel: [:],
                            lastPollTimestamp: current.timestamp
                        )
                        for aggregate in tokenAggregates {
                            accumulationWindow?.tokensByModel[aggregate.model] = aggregate
                        }
                        return .monotonicViolation
                    }

                    // Accumulate tokens into existing window
                    for aggregate in tokenAggregates {
                        if var existing = window.tokensByModel[aggregate.model] {
                            existing.inputTokens += aggregate.inputTokens
                            existing.outputTokens += aggregate.outputTokens
                            existing.cacheCreateTokens += aggregate.cacheCreateTokens
                            existing.cacheReadTokens += aggregate.cacheReadTokens
                            existing.messageCount += aggregate.messageCount
                            window.tokensByModel[aggregate.model] = existing
                        } else {
                            window.tokensByModel[aggregate.model] = aggregate
                        }
                    }
                    window.lastPollTimestamp = current.timestamp
                    accumulationWindow = window
                    return .accumulated
                } else {
                    // Start new accumulation window
                    var tokensByModel: [String: TokenAggregate] = [:]
                    for aggregate in tokenAggregates {
                        tokensByModel[aggregate.model] = aggregate
                    }
                    accumulationWindow = AccumulationWindow(
                        startTimestamp: previous.timestamp,
                        startFiveHourUtil: previousFiveHour,
                        startSevenDayUtil: previous.sevenDayUtil,
                        tokensByModel: tokensByModel,
                        lastPollTimestamp: current.timestamp
                    )
                    return .started
                }
            }
            switch action {
            case .capExceeded:
                Self.logger.info("Accumulation window exceeded 30min cap — discarding and restarting")
            case .monotonicViolation:
                Self.logger.info("Utilization decreased during accumulation — discarding window")
            case .accumulated, .started:
                Self.logger.debug("Tokens accumulated — no utilization delta yet")
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

    private func storePerModelMeasurements(
        tokensByModel: [String: TokenAggregate],
        fiveHourBefore: Double,
        fiveHourAfter: Double,
        fiveHourDelta: Double,
        sevenDayBefore: Double?,
        sevenDayAfter: Double?,
        sevenDayDelta: Double?,
        windowStart: Int64,
        timestamp: Int64
    ) async {
        let isMultiModel = tokensByModel.count > 1

        for (_, aggregate) in tokensByModel {
            let totalRaw = aggregate.inputTokens + aggregate.outputTokens + aggregate.cacheCreateTokens + aggregate.cacheReadTokens
            let tppFiveHour: Double? = fiveHourDelta >= Self.minDelta ? Double(totalRaw) / fiveHourDelta : nil
            let tppSevenDay: Double? = {
                guard let sd = sevenDayDelta, sd >= Self.minDelta else { return nil }
                return Double(totalRaw) / sd
            }()

            let confidence: MeasurementConfidence
            if isMultiModel {
                confidence = .low
            } else if fiveHourDelta >= Self.mediumConfidenceDelta {
                confidence = .medium
            } else {
                confidence = .low
            }

            let measurement = TPPMeasurement(
                id: nil,
                timestamp: timestamp,
                windowStart: windowStart,
                model: aggregate.model,
                variant: nil,
                source: .passive,
                fiveHourBefore: fiveHourBefore,
                fiveHourAfter: fiveHourAfter,
                fiveHourDelta: fiveHourDelta,
                sevenDayBefore: sevenDayBefore,
                sevenDayAfter: sevenDayAfter,
                sevenDayDelta: sevenDayDelta,
                inputTokens: aggregate.inputTokens,
                outputTokens: aggregate.outputTokens,
                cacheCreateTokens: aggregate.cacheCreateTokens,
                cacheReadTokens: aggregate.cacheReadTokens,
                totalRawTokens: totalRaw,
                tppFiveHour: tppFiveHour,
                tppSevenDay: tppSevenDay,
                confidence: confidence,
                messageCount: aggregate.messageCount
            )

            do {
                try await tppStorage.storePassiveResult(measurement)
                Self.logger.info("Stored passive TPP: model=\(aggregate.model, privacy: .public) tpp5h=\(tppFiveHour ?? -1) confidence=\(confidence.rawValue, privacy: .public)")
            } catch {
                Self.logger.error("Failed to store passive TPP measurement: \(error.localizedDescription)")
            }
        }
    }

    private func storeDeltaOnlyRecord(
        fiveHourBefore: Double,
        fiveHourAfter: Double,
        fiveHourDelta: Double,
        sevenDayBefore: Double?,
        sevenDayAfter: Double?,
        sevenDayDelta: Double?,
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
            fiveHourBefore: fiveHourBefore,
            fiveHourAfter: fiveHourAfter,
            fiveHourDelta: fiveHourDelta,
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
            Self.logger.info("Stored delta-only record (non-Claude-Code usage): 5h delta=\(fiveHourDelta)")
        } catch {
            Self.logger.error("Failed to store delta-only TPP record: \(error.localizedDescription)")
        }
    }
}

// MARK: - Accumulation Window

extension PassiveTPPEngine {
    struct AccumulationWindow {
        let startTimestamp: Int64
        let startFiveHourUtil: Double
        let startSevenDayUtil: Double?
        var tokensByModel: [String: TokenAggregate]
        var lastPollTimestamp: Int64
    }
}
