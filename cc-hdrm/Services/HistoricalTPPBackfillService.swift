import Foundation
import os

/// Computes approximate TPP values from existing raw poll history and rollup data.
/// Runs once on first launch after TPP feature is enabled. Fire-and-forget — errors
/// are logged but never propagate to callers.
final class HistoricalTPPBackfillService: HistoricalTPPBackfillServiceProtocol, @unchecked Sendable {
    private let historicalDataService: any HistoricalDataServiceProtocol
    private let logParser: any ClaudeCodeLogParserProtocol
    private let tppStorage: any TPPStorageServiceProtocol
    private let preferencesManager: PreferencesManagerProtocol
    private let lock = NSLock()
    private var isRunning = false

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "tpp-backfill"
    )

    /// Minimum weekly utilization delta to trigger a TPP measurement.
    private static let minDelta: Double = 1.0

    /// Minimum weekly delta for medium confidence (single model).
    private static let mediumConfidenceDelta: Double = 2.0

    /// Maximum window duration without a weekly step (6 hours in milliseconds), matching `PassiveTPPEngine`.
    private static let maxWindowMs: Int64 = 6 * 60 * 60 * 1000

    init(
        historicalDataService: any HistoricalDataServiceProtocol,
        logParser: any ClaudeCodeLogParserProtocol,
        tppStorage: any TPPStorageServiceProtocol,
        preferencesManager: PreferencesManagerProtocol
    ) {
        self.historicalDataService = historicalDataService
        self.logParser = logParser
        self.tppStorage = tppStorage
        self.preferencesManager = preferencesManager
    }

    func runBackfillIfNeeded() async {
        // Fast path: preference check
        if preferencesManager.tppBackfillCompleted {
            Self.logger.debug("Backfill already completed (preference check)")
            return
        }

        // Slow path: DB check for existing backfill records (check both sources)
        do {
            let existingPassive = try await tppStorage.getMeasurements(
                from: 0,
                to: Int64.max,
                source: .passiveBackfill,
                model: nil,
                confidence: nil
            )
            let existingRollup = existingPassive.isEmpty
                ? try await tppStorage.getMeasurements(
                    from: 0,
                    to: Int64.max,
                    source: .rollupBackfill,
                    model: nil,
                    confidence: nil
                )
                : []
            if !existingPassive.isEmpty || !existingRollup.isEmpty {
                Self.logger.info("Backfill records found in DB — marking preference and skipping")
                preferencesManager.tppBackfillCompleted = true
                return
            }
        } catch {
            Self.logger.warning("Failed to query existing backfill records: \(error.localizedDescription)")
            // Continue to run backfill — better to have duplicates than miss data
        }

        await runBackfill(force: false)
    }

    @discardableResult
    func runBackfill(force: Bool) async -> Int {
        // Prevent concurrent runs
        let canRun = lock.withLock { () -> Bool in
            guard !isRunning else { return false }
            isRunning = true
            return true
        }
        guard canRun else {
            Self.logger.info("Backfill already in progress — skipping")
            return 0
        }
        defer { lock.withLock { isRunning = false } }

        Self.logger.info("Starting historical TPP backfill (force=\(force))")
        let startTime = CFAbsoluteTimeGetCurrent()

        if force {
            do {
                try await tppStorage.deleteBackfillRecords()
                preferencesManager.tppBackfillCompleted = false
                Self.logger.info("Deleted existing backfill records for force re-run")
            } catch {
                Self.logger.error("Failed to delete existing backfill records: \(error.localizedDescription)")
                return 0
            }
        }

        var totalMeasurements = 0

        // Phase 1: Raw poll backfill (last ~24 hours)
        do {
            let pollCount = try await processRawPolls()
            totalMeasurements += pollCount
            Self.logger.info("Raw poll backfill complete: \(pollCount) measurements stored")
        } catch {
            Self.logger.error("Raw poll backfill failed: \(error.localizedDescription)")
        }

        // Phase 2: Rollup-based backfill (older data)
        do {
            let rollupCount = try await processRollups()
            totalMeasurements += rollupCount
            Self.logger.info("Rollup backfill complete: \(rollupCount) measurements stored")
        } catch {
            Self.logger.error("Rollup backfill failed: \(error.localizedDescription)")
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Self.logger.info("Historical TPP backfill complete: \(totalMeasurements) total measurements in \(String(format: "%.2f", elapsed))s")

        preferencesManager.tppBackfillCompleted = true

        return totalMeasurements
    }

    // MARK: - Raw Poll Backfill

    private func processRawPolls() async throws -> Int {
        let polls = try await historicalDataService.getRecentPolls(hours: 24)
        guard polls.count >= 2 else {
            Self.logger.info("Fewer than 2 raw polls — skipping raw poll backfill")
            return 0
        }

        var measurementCount = 0

        // Window runs from the last weekly step, reset or missing-7d point, so a 1% step
        // gets the tokens of every poll interval since then.
        var windowStart: (timestamp: Int64, sevenDay: Double)? = polls[0].sevenDayUtil.map { (polls[0].timestamp, $0) }

        for i in 1..<polls.count {
            let previous = polls[i - 1]
            let current = polls[i]

            guard let currentSevenDay = current.sevenDayUtil else {
                windowStart = nil
                continue
            }
            guard var start = windowStart, let previousSevenDay = previous.sevenDayUtil else {
                windowStart = (current.timestamp, currentSevenDay)
                continue
            }

            // Weekly utilization only falls at a reset
            if currentSevenDay < previousSevenDay {
                Self.logger.debug("Backfill: weekly reset between \(previous.timestamp) and \(current.timestamp) — restarting window")
                windowStart = (current.timestamp, currentSevenDay)
                continue
            }

            // Same as the live engine: a step never absorbs tokens from a window older than the cap
            if current.timestamp - start.timestamp > Self.maxWindowMs {
                Self.logger.debug("Backfill: window from \(start.timestamp) exceeded 6h cap — restarting at \(previous.timestamp)")
                start = (previous.timestamp, previousSevenDay)
                windowStart = start
            }

            let sevenDayDelta = currentSevenDay - start.sevenDay
            guard sevenDayDelta >= Self.minDelta else { continue }
            windowStart = (current.timestamp, currentSevenDay)

            // Query log parser for tokens in [window start, current.timestamp)
            let tokenAggregates = logParser.getTokens(from: start.timestamp, to: current.timestamp)
            let totalTokensAcrossModels = tokenAggregates.reduce(0) {
                $0 + $1.inputTokens + $1.outputTokens + $1.cacheCreateTokens + $1.cacheReadTokens
            }

            if totalTokensAcrossModels > 0 {
                // Store per-model measurements
                let isMultiModel = tokenAggregates.count > 1

                for aggregate in tokenAggregates {
                    let totalRaw = aggregate.inputTokens + aggregate.outputTokens + aggregate.cacheCreateTokens + aggregate.cacheReadTokens
                    // cache_read is free; cache_create costs 1.25x base input
                    let effectiveTokens = Double(aggregate.inputTokens + aggregate.outputTokens) + Double(aggregate.cacheCreateTokens) * 1.25
                    let tppSevenDay = effectiveTokens / sevenDayDelta

                    let confidence: MeasurementConfidence =
                        !isMultiModel && sevenDayDelta >= Self.mediumConfidenceDelta ? .medium : .low

                    let measurement = TPPMeasurement(
                        id: nil,
                        timestamp: current.timestamp,
                        windowStart: start.timestamp,
                        model: aggregate.model,
                        variant: nil,
                        source: .passiveBackfill,
                        fiveHourBefore: nil,
                        fiveHourAfter: nil,
                        fiveHourDelta: nil,
                        sevenDayBefore: start.sevenDay,
                        sevenDayAfter: currentSevenDay,
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
                        measurementCount += 1
                    } catch {
                        Self.logger.error("Failed to store backfill measurement: \(error.localizedDescription)")
                    }
                }
            } else {
                // Delta-only record (AC-4): utilization changed but no token data
                let measurement = TPPMeasurement(
                    id: nil,
                    timestamp: current.timestamp,
                    windowStart: start.timestamp,
                    model: "unknown",
                    variant: nil,
                    source: .passiveBackfill,
                    fiveHourBefore: nil,
                    fiveHourAfter: nil,
                    fiveHourDelta: nil,
                    sevenDayBefore: start.sevenDay,
                    sevenDayAfter: currentSevenDay,
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
                    measurementCount += 1
                } catch {
                    Self.logger.error("Failed to store delta-only backfill record: \(error.localizedDescription)")
                }
            }
        }

        return measurementCount
    }

    // MARK: - Rollup-Based Backfill

    private func processRollups() async throws -> Int {
        var measurementCount = 0

        // Use .month only: it already includes all .week data (raw <24h + 5min 1-7d + hourly 7-30d).
        // Querying .week separately would produce duplicate records for the 0-7d window.
        let rollups = try await historicalDataService.getRolledUpData(range: .month)

        for rollup in rollups {
            // Skip buckets with resets (delta unreliable)
            guard rollup.resetCount == 0 else { continue }

            // Skip buckets with missing peak/min
            guard let peak = rollup.sevenDayPeak, let min = rollup.sevenDayMin else { continue }

            // Approximate delta as peak - min
            let approximateDelta = peak - min
            guard approximateDelta >= Self.minDelta else { continue }

            // Query log parser for tokens in this rollup's window
            let tokenAggregates = logParser.getTokens(from: rollup.periodStart, to: rollup.periodEnd)
            let totalTokensAcrossModels = tokenAggregates.reduce(0) {
                $0 + $1.inputTokens + $1.outputTokens + $1.cacheCreateTokens + $1.cacheReadTokens
            }

            if totalTokensAcrossModels > 0 {
                for aggregate in tokenAggregates {
                    let totalRaw = aggregate.inputTokens + aggregate.outputTokens + aggregate.cacheCreateTokens + aggregate.cacheReadTokens
                    // cache_read is free; cache_create costs 1.25x base input
                    let effectiveTokens = Double(aggregate.inputTokens + aggregate.outputTokens) + Double(aggregate.cacheCreateTokens) * 1.25
                    let tppSevenDay = effectiveTokens / approximateDelta

                    let measurement = TPPMeasurement(
                        id: nil,
                        timestamp: rollup.periodEnd,
                        windowStart: rollup.periodStart,
                        model: aggregate.model,
                        variant: nil,
                        source: .rollupBackfill,
                        fiveHourBefore: nil,
                        fiveHourAfter: nil,
                        fiveHourDelta: nil,
                        sevenDayBefore: min,
                        sevenDayAfter: peak,
                        sevenDayDelta: approximateDelta,
                        inputTokens: aggregate.inputTokens,
                        outputTokens: aggregate.outputTokens,
                        cacheCreateTokens: aggregate.cacheCreateTokens,
                        cacheReadTokens: aggregate.cacheReadTokens,
                        totalRawTokens: totalRaw,
                        tppFiveHour: nil,
                        tppSevenDay: tppSevenDay,
                        confidence: .low,
                        messageCount: aggregate.messageCount
                    )

                    do {
                        try await tppStorage.storePassiveResult(measurement)
                        measurementCount += 1
                    } catch {
                        Self.logger.error("Failed to store rollup backfill measurement: \(error.localizedDescription)")
                    }
                }
            } else {
                // Delta-only record for rollup
                let measurement = TPPMeasurement(
                    id: nil,
                    timestamp: rollup.periodEnd,
                    windowStart: rollup.periodStart,
                    model: "unknown",
                    variant: nil,
                    source: .rollupBackfill,
                    fiveHourBefore: nil,
                    fiveHourAfter: nil,
                    fiveHourDelta: nil,
                    sevenDayBefore: min,
                    sevenDayAfter: peak,
                    sevenDayDelta: approximateDelta,
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
                    measurementCount += 1
                } catch {
                    Self.logger.error("Failed to store rollup delta-only record: \(error.localizedDescription)")
                }
            }
        }

        return measurementCount
    }
}
