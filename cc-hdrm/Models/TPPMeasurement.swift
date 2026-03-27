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

    /// Computes TPP for the 5-hour window from raw data.
    /// Returns nil if delta is zero or negative (below detection threshold).
    var computedTppFiveHour: Double? {
        guard let delta = fiveHourDelta, delta > 0 else { return nil }
        return Double(totalRawTokens) / delta
    }

    /// Computes TPP for the 7-day window from raw data.
    /// Returns nil if delta is zero or negative (below detection threshold).
    var computedTppSevenDay: Double? {
        guard let delta = sevenDayDelta, delta > 0 else { return nil }
        return Double(totalRawTokens) / delta
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
        let totalRaw = inputTokens + outputTokens + cacheCreateTokens + cacheReadTokens
        let tpp5h = fiveHourDelta > 0 ? Double(totalRaw) / fiveHourDelta : nil
        let tpp7d: Double? = {
            guard let delta = sevenDayDelta, delta > 0 else { return nil }
            return Double(totalRaw) / delta
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
