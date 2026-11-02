import Foundation

/// Benchmark variant types for token efficiency measurement.
enum BenchmarkVariant: String, Sendable, CaseIterable {
    case outputHeavy = "output-heavy"
    case inputHeavy = "input-heavy"
    case cacheHeavy = "cache-heavy"

    var displayName: String {
        switch self {
        case .outputHeavy: return "Output-heavy"
        case .inputHeavy: return "Input-heavy"
        case .cacheHeavy: return "Cache-heavy"
        }
    }
}

/// Source of a TPP measurement.
enum MeasurementSource: String, Sendable {
    case benchmark
    case passive
    case passiveBackfill = "passive-backfill"
    case rollupBackfill = "rollup-backfill"
}

/// Confidence level for a TPP measurement.
enum MeasurementConfidence: String, Sendable {
    case high
    case medium
    case low
}

/// The utilization step a TPP value was measured against.
/// Weekly values run about 10x higher than 5-hour values, so the two are never combined.
enum TPPBasis: String, Sendable, CaseIterable {
    case weekly
    case fiveHour
}

/// A single token-per-percent (TPP) measurement result.
struct TPPMeasurement: Sendable, Equatable {
    let id: Int64?
    let timestamp: Int64
    let windowStart: Int64?
    let model: String
    let variant: String?
    let source: MeasurementSource
    let fiveHourBefore: Double?
    let fiveHourAfter: Double?
    let fiveHourDelta: Double?
    let sevenDayBefore: Double?
    let sevenDayAfter: Double?
    let sevenDayDelta: Double?
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreateTokens: Int
    let cacheReadTokens: Int
    let totalRawTokens: Int
    let tppFiveHour: Double?
    let tppSevenDay: Double?
    let confidence: MeasurementConfidence
    let messageCount: Int

    /// Every row written before weekly measurement has a 5-hour delta, so the absence of one
    /// identifies a weekly row. This holds after the account changes state.
    var basis: TPPBasis {
        fiveHourDelta != nil ? .fiveHour : .weekly
    }

    /// The TPP value on this row's own basis. A 5-hour row's `tppSevenDay` covers a 5-hour
    /// style window, so it must not stand in for a weekly reading.
    var chartTPP: Double? {
        basis == .fiveHour ? tppFiveHour : tppSevenDay
    }

    /// Effective tokens that count toward rate limits.
    /// cache_read is free; cache_create costs 1.25x base input.
    var effectiveRateLimitTokens: Double {
        Double(inputTokens + outputTokens) + Double(cacheCreateTokens) * 1.25
    }

    /// Computes TPP for the 5-hour window from rate-limit-effective tokens.
    /// Returns nil if delta is zero or negative (below detection threshold).
    var computedTppFiveHour: Double? {
        guard let delta = fiveHourDelta, delta > 0 else { return nil }
        return effectiveRateLimitTokens / delta
    }

    /// Computes TPP for the 7-day window from rate-limit-effective tokens.
    /// Returns nil if delta is zero or negative (below detection threshold).
    var computedTppSevenDay: Double? {
        guard let delta = sevenDayDelta, delta > 0 else { return nil }
        return effectiveRateLimitTokens / delta
    }

    /// Creates a TPPMeasurement with computed TPP values from the raw token/delta data.
    static func fromBenchmark(
        model: String,
        variant: BenchmarkVariant,
        fiveHourBefore: Double,
        fiveHourAfter: Double,
        sevenDayBefore: Double?,
        sevenDayAfter: Double?,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreateTokens: Int = 0,
        cacheReadTokens: Int = 0
    ) -> TPPMeasurement {
        let fiveHourDelta = fiveHourAfter - fiveHourBefore
        let sevenDayDelta: Double? = {
            guard let before = sevenDayBefore, let after = sevenDayAfter else { return nil }
            return after - before
        }()
        // cache_read is free; cache_create costs 1.25x base input
        let effectiveTokens = Double(inputTokens + outputTokens) + Double(cacheCreateTokens) * 1.25
        let totalRaw = inputTokens + outputTokens + cacheCreateTokens + cacheReadTokens
        let tpp5h = fiveHourDelta > 0 ? effectiveTokens / fiveHourDelta : nil
        let tpp7d: Double? = {
            guard let delta = sevenDayDelta, delta > 0 else { return nil }
            return effectiveTokens / delta
        }()

        return TPPMeasurement(
            id: nil,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            windowStart: Int64(Date().timeIntervalSince1970 * 1000),
            model: model,
            variant: variant.rawValue,
            source: .benchmark,
            fiveHourBefore: fiveHourBefore,
            fiveHourAfter: fiveHourAfter,
            fiveHourDelta: fiveHourDelta,
            sevenDayBefore: sevenDayBefore,
            sevenDayAfter: sevenDayAfter,
            sevenDayDelta: sevenDayDelta,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreateTokens: cacheCreateTokens,
            cacheReadTokens: cacheReadTokens,
            totalRawTokens: totalRaw,
            tppFiveHour: tpp5h,
            tppSevenDay: tpp7d,
            confidence: .high,
            messageCount: 1
        )
    }
}
