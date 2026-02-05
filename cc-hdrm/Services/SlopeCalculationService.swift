import Foundation
import os

/// Service that tracks recent poll data in a ring buffer and calculates usage slope.
/// Thread-safe via NSLock, following Epic 10 patterns.
final class SlopeCalculationService: SlopeCalculationServiceProtocol, @unchecked Sendable {

    // MARK: - Ring Buffer Entry

    /// A single entry in the ring buffer.
    private struct BufferEntry: Sendable {
        /// Unix milliseconds when the poll was recorded
        let timestamp: Int64
        /// 5-hour window utilization percentage (0-100)
        let fiveHourUtil: Double?
        /// 7-day window utilization percentage (0-100)
        let sevenDayUtil: Double?
    }

    // MARK: - Properties

    /// In-memory ring buffer for recent poll data
    private var buffer: [BufferEntry] = []

    /// Thread safety lock (NSLock pattern from Epic 10)
    private let lock = NSLock()

    /// Maximum age for buffer entries: 15 minutes in milliseconds
    private static let maxAgeMs: Int64 = 15 * 60 * 1000

    /// Minimum data span required for valid slope calculation: 10 minutes in milliseconds
    private static let minDataSpanMs: Int64 = 10 * 60 * 1000

    /// Minimum number of entries required for valid slope calculation
    private static let minEntryCount: Int = 20

    // MARK: - Slope Thresholds (% per minute)
    //
    // Threshold rationale (calibrated to Claude Code usage patterns):
    // - 5h window = 300 minutes. At 0.3%/min, exhausts in ~333 min (5.5h) — sustainable pace
    // - At 1.5%/min, exhausts in ~67 min (1.1h) — heavy session, warning warranted
    // - Below 0.3%/min is effectively idle or light background use
    // These values may be tuned based on user feedback post-release.

    /// Rate below which slope is considered flat (includes negative rates from reset edge case)
    private static let flatThreshold: Double = 0.3

    /// Rate above which slope is considered steep (below this and above flat is rising)
    private static let steepThreshold: Double = 1.5

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "slope"
    )

    // MARK: - Initialization

    init() {
        Self.logger.debug("SlopeCalculationService initialized")
    }

    // MARK: - SlopeCalculationServiceProtocol

    func addPoll(_ poll: UsagePoll) {
        lock.withLock {
            // Create buffer entry from poll
            let entry = BufferEntry(
                timestamp: poll.timestamp,
                fiveHourUtil: poll.fiveHourUtil,
                sevenDayUtil: poll.sevenDayUtil
            )
            buffer.append(entry)

            // Evict stale entries older than 15 minutes
            let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Self.maxAgeMs
            buffer.removeAll { $0.timestamp < cutoff }

            Self.logger.debug("Poll added to buffer: timestamp=\(poll.timestamp), buffer size=\(self.buffer.count)")
        }
    }

    func calculateSlope(for window: UsageWindow, normalizationFactor: Double?) -> SlopeLevel {
        lock.withLock {
            // Extract entries with non-nil utilization for the target window
            let entries: [(timestamp: Int64, util: Double)] = buffer.compactMap { entry in
                let util: Double?
                switch window {
                case .fiveHour:
                    util = entry.fiveHourUtil
                case .sevenDay:
                    util = entry.sevenDayUtil
                }
                guard let utilValue = util else { return nil }
                return (entry.timestamp, utilValue)
            }

            // Require minimum entry count for valid calculation
            guard entries.count >= Self.minEntryCount else {
                Self.logger.debug("Insufficient entries for \(window.rawValue) slope: \(entries.count) < \(Self.minEntryCount)")
                return .flat
            }

            // Get oldest and newest entries by timestamp (defensive against out-of-order inserts)
            guard
                let oldest = entries.min(by: { $0.timestamp < $1.timestamp }),
                let newest = entries.max(by: { $0.timestamp < $1.timestamp })
            else {
                return .flat
            }

            // Calculate time span in minutes
            let timeSpanMs = newest.timestamp - oldest.timestamp
            let timeSpanMinutes = Double(timeSpanMs) / (60.0 * 1000.0)

            // Require minimum time span for valid calculation
            guard timeSpanMs >= Self.minDataSpanMs else {
                Self.logger.debug("Insufficient time span for \(window.rawValue) slope: \(timeSpanMinutes) min < 10 min")
                return .flat
            }

            // Calculate rate of change (% per minute)
            let ratePerMinute = (newest.util - oldest.util) / timeSpanMinutes

            // Apply credit normalization for 7d window so slope thresholds are meaningful
            let effectiveRate: Double
            if window == .sevenDay, let factor = normalizationFactor {
                effectiveRate = ratePerMinute * factor
            } else {
                effectiveRate = ratePerMinute
            }

            // Map rate to slope level
            // Note: ratePerMinute should always be >= 0 (utilization only increases)
            // Negative rates can only occur if buffer spans a reset boundary - treat as flat
            let level: SlopeLevel
            switch effectiveRate {
            case ..<Self.flatThreshold:
                level = .flat
            case Self.flatThreshold..<Self.steepThreshold:
                level = .rising
            default:
                level = .steep
            }

            Self.logger.debug("\(window.rawValue) slope: raw=\(String(format: "%.3f", ratePerMinute))%/min, effective=\(String(format: "%.3f", effectiveRate))%/min, level=\(level.rawValue)")
            return level
        }
    }

    func bootstrapFromHistory(_ polls: [UsagePoll]) {
        lock.withLock {
            // Clear existing buffer
            buffer.removeAll()

            // Calculate cutoff for 15-minute window
            let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Self.maxAgeMs

            // Add only recent polls (within 15 minutes)
            for poll in polls where poll.timestamp >= cutoff {
                let entry = BufferEntry(
                    timestamp: poll.timestamp,
                    fiveHourUtil: poll.fiveHourUtil,
                    sevenDayUtil: poll.sevenDayUtil
                )
                buffer.append(entry)
            }

            Self.logger.info("Buffer bootstrapped with \(self.buffer.count) historical polls")
        }
    }
}
