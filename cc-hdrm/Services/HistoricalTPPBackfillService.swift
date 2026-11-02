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
    private var weeklyStoreFailed = false

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "tpp-backfill"
    )

    /// Minimum utilization delta to trigger a TPP measurement.
    private static let minDelta: Double = 1.0

    /// Utilization drop threshold for reset detection (50%).
    private static let resetDropThreshold: Double = 50.0

    /// Minimum 5h delta for medium confidence (single model).
    private static let mediumConfidenceDelta: Double = 3.0

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
            if preferencesManager.tppWeeklyBackfillCompleted {
                Self.logger.debug("Backfill already completed (preference check)")
            } else {
                Self.logger.info("5-hour backfill already completed — running the weekly pass once")
                await run(force: false, weeklyOnly: true)
            }
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
                Self.logger.info("Backfill records found in DB — marking preference and running only the weekly pass")
                preferencesManager.tppBackfillCompleted = true
                if !preferencesManager.tppWeeklyBackfillCompleted {
                    await run(force: false, weeklyOnly: true)
                }
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
        await run(force: force, weeklyOnly: false)
    }

    @discardableResult
    private func run(force: Bool, weeklyOnly: Bool) async -> Int {
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

        Self.logger.info("Starting historical TPP backfill (force=\(force), weeklyOnly=\(weeklyOnly))")
        let startTime = CFAbsoluteTimeGetCurrent()

        if force {
            do {
                // The rebuild only reaches back as far as these sources, so older rows must survive.
                // The first poll only opens a pair, so no row can be rebuilt at its timestamp.
                let polls = try await historicalDataService.getRecentPolls(hours: 24)
                let rollups = try await historicalDataService.getRolledUpData(range: .month)
                try await tppStorage.deleteBackfillRecords(
                    passiveFrom: polls.count >= 2 ? polls[1].timestamp : nil,
                    rollupFrom: rollups.map(\.periodEnd).min()
                )
                preferencesManager.tppBackfillCompleted = false
                Self.logger.info("Deleted rebuildable backfill records for force re-run")
            } catch {
                Self.logger.error("Failed to delete existing backfill records: \(error.localizedDescription)")
                return 0
            }
        }

        var totalMeasurements = 0

        // Weekly rows are skipped this run if the overlap check has nothing to check against,
        // and the pass stays open so a later launch retries it.
        var existingWeekly: [TPPMeasurement]?
        do {
            existingWeekly = try await tppStorage.getMeasurements(from: 0, to: Int64.max, source: nil, model: nil, confidence: nil)
                .filter { $0.basis == .weekly }
        } catch {
            Self.logger.error("Failed to read existing weekly rows, skipping weekly backfill this run: \(error.localizedDescription)")
        }
        weeklyStoreFailed = false
        var weeklyPassFinished = existingWeekly != nil

        // Phase 1: Raw poll backfill (last ~24 hours)
        do {
            let pollCount = try await processRawPolls(weeklyOnly: weeklyOnly, existingWeekly: existingWeekly)
            totalMeasurements += pollCount
            Self.logger.info("Raw poll backfill complete: \(pollCount) measurements stored")
        } catch {
            weeklyPassFinished = false
            Self.logger.error("Raw poll backfill failed: \(error.localizedDescription)")
        }

        // Phase 2: Rollup-based backfill (older data)
        if !weeklyOnly {
            do {
                let rollupCount = try await processRollups()
                totalMeasurements += rollupCount
                Self.logger.info("Rollup backfill complete: \(rollupCount) measurements stored")
            } catch {
                Self.logger.error("Rollup backfill failed: \(error.localizedDescription)")
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Self.logger.info("Historical TPP backfill complete: \(totalMeasurements) total measurements in \(String(format: "%.2f", elapsed))s")

        preferencesManager.tppBackfillCompleted = true
        if weeklyPassFinished && !weeklyStoreFailed {
            preferencesManager.tppWeeklyBackfillCompleted = true
        }

        return totalMeasurements
    }

    // MARK: - Weekly Rows

    /// Stores weekly rows except those overlapping a weekly row already in the database,
    /// because the same step would otherwise count twice in chart averages. A stored row with
    /// no value blocks only another row with no value, so it cannot hide a real reading.
    private func storeWeekly(_ measurements: [TPPMeasurement], existing: [TPPMeasurement]?) async -> Int {
        guard let existing else { return 0 }
        var stored = 0
        for measurement in measurements {
            let start = measurement.windowStart ?? measurement.timestamp
            let overlaps = existing.contains {
                ($0.windowStart ?? $0.timestamp) < measurement.timestamp && start < $0.timestamp
                    && ($0.chartTPP != nil || measurement.chartTPP == nil)
            }
            guard !overlaps else {
                Self.logger.debug("Skipping weekly backfill row at \(measurement.timestamp): overlaps a stored weekly row")
                continue
            }
            do {
                try await tppStorage.storePassiveResult(measurement)
                stored += 1
            } catch {
                weeklyStoreFailed = true
                Self.logger.error("Failed to store weekly backfill measurement, the weekly pass stays open: \(error.localizedDescription)")
            }
        }
        return stored
    }

    // MARK: - Raw Poll Backfill

    private func processRawPolls(weeklyOnly: Bool, existingWeekly: [TPPMeasurement]?) async throws -> Int {
        let polls = try await historicalDataService.getRecentPolls(hours: 24)
        guard polls.count >= 2 else {
            Self.logger.info("Fewer than 2 raw polls — skipping raw poll backfill")
            return 0
        }

        var measurementCount = 0
        var weeklyTracker = WeeklyStepTracker(source: .passiveBackfill)

        for i in 1..<polls.count {
            let previous = polls[i - 1]
            let current = polls[i]

            guard let currentFiveHour = current.fiveHourUtil,
                  let previousFiveHour = previous.fiveHourUtil else {
                let tokens = logParser.getTokens(from: previous.timestamp, to: current.timestamp)
                let outcome = weeklyTracker.process(current: current, previous: previous, tokens: tokens)
                measurementCount += await storeWeekly(outcome.measurements, existing: existingWeekly)
                continue
            }
            weeklyTracker.reset()
            if weeklyOnly { continue }

            // Reset detection: 5h utilization drops by >= 50%
            if previousFiveHour - currentFiveHour >= Self.resetDropThreshold {
                continue
            }

            let fiveHourDelta = currentFiveHour - previousFiveHour
            let sevenDayDelta: Double? = {
                guard let curr = current.sevenDayUtil, let prev = previous.sevenDayUtil else { return nil }
                return curr - prev
            }()

            guard fiveHourDelta >= Self.minDelta || (sevenDayDelta ?? 0) >= Self.minDelta else {
                continue
            }

            // Query log parser for tokens in [previous.timestamp, current.timestamp)
            let tokenAggregates = logParser.getTokens(from: previous.timestamp, to: current.timestamp)
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
                    let tppFiveHour: Double? = fiveHourDelta >= Self.minDelta ? effectiveTokens / fiveHourDelta : nil
                    let tppSevenDay: Double? = {
                        guard let sd = sevenDayDelta, sd >= Self.minDelta else { return nil }
                        return effectiveTokens / sd
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
                        timestamp: current.timestamp,
                        windowStart: previous.timestamp,
                        model: aggregate.model,
                        variant: nil,
                        source: .passiveBackfill,
                        fiveHourBefore: previousFiveHour,
                        fiveHourAfter: currentFiveHour,
                        fiveHourDelta: fiveHourDelta,
                        sevenDayBefore: previous.sevenDayUtil,
                        sevenDayAfter: current.sevenDayUtil,
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
                    windowStart: previous.timestamp,
                    model: "unknown",
                    variant: nil,
                    source: .passiveBackfill,
                    fiveHourBefore: previousFiveHour,
                    fiveHourAfter: currentFiveHour,
                    fiveHourDelta: fiveHourDelta,
                    sevenDayBefore: previous.sevenDayUtil,
                    sevenDayAfter: current.sevenDayUtil,
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
            guard let peak = rollup.fiveHourPeak, let min = rollup.fiveHourMin else { continue }

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
                    let tppFiveHour = effectiveTokens / approximateDelta

                    let measurement = TPPMeasurement(
                        id: nil,
                        timestamp: rollup.periodEnd,
                        windowStart: rollup.periodStart,
                        model: aggregate.model,
                        variant: nil,
                        source: .rollupBackfill,
                        fiveHourBefore: min,
                        fiveHourAfter: peak,
                        fiveHourDelta: approximateDelta,
                        sevenDayBefore: rollup.sevenDayMin,
                        sevenDayAfter: rollup.sevenDayPeak,
                        sevenDayDelta: nil,
                        inputTokens: aggregate.inputTokens,
                        outputTokens: aggregate.outputTokens,
                        cacheCreateTokens: aggregate.cacheCreateTokens,
                        cacheReadTokens: aggregate.cacheReadTokens,
                        totalRawTokens: totalRaw,
                        tppFiveHour: tppFiveHour,
                        tppSevenDay: nil,
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
                    fiveHourBefore: min,
                    fiveHourAfter: peak,
                    fiveHourDelta: approximateDelta,
                    sevenDayBefore: rollup.sevenDayMin,
                    sevenDayAfter: rollup.sevenDayPeak,
                    sevenDayDelta: nil,
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
